`timescale 1ns / 1ps

module sdram_master_mem_access (
    input               clk,
    input               rstb,
    input               mem_wr_req,
    input               mem_rd_req,
    input      [31:0]   paddr,
    input      [31:0]   pwdata,
    input      [3:0]    burst_len_cfg,
    input               cmdfull,
    input               txfull,
    input               rxempty,
    input      [15:0]   rxrdata,
    input      [3:0]    tx_diff,
    input      [3:0]    rx_diff,
    output              pready,
    output reg [31:0]   prdata,
    output     [28:0]   cmdwdata,
    output              cmdwe,
    output     [15:0]   txwdata,
    output              txwe,
    output              rxre,
    output              busy
);

localparam [4:0] st_idle         = 5'd0;
localparam [4:0] st_tx_lo        = 5'd1;
localparam [4:0] st_tx_hi        = 5'd2;
localparam [4:0] st_wr_ack       = 5'd3;
localparam [4:0] st_wr_wait_req  = 5'd4;
localparam [4:0] st_wr_wait_fifo = 5'd5;
localparam [4:0] st_wr_cmd0      = 5'd6;
localparam [4:0] st_wr_cmd1      = 5'd7;
localparam [4:0] st_wr_done      = 5'd8;

localparam [4:0] st_rd_cmd0      = 5'd9;
localparam [4:0] st_rd_cmd1      = 5'd10;
localparam [4:0] st_rd_wait_fifo = 5'd11;
localparam [4:0] st_rd_pop0      = 5'd12;
localparam [4:0] st_rd_cap0      = 5'd13;
localparam [4:0] st_rd_pop1      = 5'd14;
localparam [4:0] st_rd_cap1      = 5'd15;
localparam [4:0] st_rd_word_done = 5'd16;
localparam [4:0] st_rd_wait_req  = 5'd17;
localparam [4:0] st_wr_resume_wr = 5'd18;
localparam [4:0] st_wr_resume_rd = 5'd19;
// Give CPU-side sequential stores enough time to fill one SDRAM burst
// before flushing a trailing partial write with DQM masking.
localparam [7:0] wr_wait_timeout_cycles = 8'd128;

reg  [4:0] state, state_n;
reg  [31:0] paddr_req;
reg  [2:0] wr_word_count;
reg  [2:0] rd_word_count;
reg  [15:0] rd_lo_data;
reg  [1:0] wr_deferred_req;
reg  [7:0] wr_wait_timeout_cnt;

localparam [1:0] wr_defer_none  = 2'd0;
localparam [1:0] wr_defer_write = 2'd1;
localparam [1:0] wr_defer_read  = 2'd2;

wire split_bl1 = (burst_len_cfg == 4'd1); //BL=1
wire [2:0]  burst_words =
(burst_len_cfg == 4'd8) ? 3'd4 :
(burst_len_cfg == 4'd4) ? 3'd2 : 3'd1;

wire [3:0] total_halfwords = (split_bl1) ? 4'd2 : burst_len_cfg;
wire write_burst_done = ((wr_word_count + 3'd1) >= burst_words);
wire [3:0] wr_valid_halfwords = split_bl1 ? 4'd2 : {wr_word_count, 1'b0};
wire [3:0] wr_cmd_valid_halfwords = split_bl1 ? 4'd1 : wr_valid_halfwords;
wire [3:0] rd_cmd_valid_halfwords = split_bl1 ? 4'd1 : total_halfwords;
wire tx_ready = split_bl1 ? (tx_diff >= 4'd2) : (tx_diff >= wr_valid_halfwords);
wire rx_ready = (rx_diff >= total_halfwords);
wire rd_last_word = (rd_word_count == burst_words);
wire wr_addr_contig = (paddr == (paddr_req + {27'd0, wr_word_count, 2'b00}));
wire start_wr_burst = ((state == st_idle) && mem_wr_req) || (state == st_wr_resume_wr);
wire start_rd_burst = ((state == st_idle) && mem_rd_req) || (state == st_wr_resume_rd);
wire wr_timeout_pending = (state == st_wr_wait_req) && !split_bl1 && (wr_word_count != 3'd0) &&
                          (wr_word_count < burst_words) && !mem_wr_req && !mem_rd_req;
wire wr_timeout_expired = wr_timeout_pending && (wr_wait_timeout_cnt >= wr_wait_timeout_cycles);

//paddr (req_addr)
wire [31:0] req_offset = paddr_req - 32'h6000_0000;
wire [23:0] half_addr0 = req_offset[25:1];
wire [23:0] half_addr1 = half_addr0 + 24'd1;

wire tx_push_lo   = (state == st_tx_lo) && !txfull;
wire tx_push_hi   = (state == st_tx_hi) && !txfull;
wire cmd_wr0_fire = (state == st_wr_cmd0);
wire cmd_wr1_fire = (state == st_wr_cmd1);
wire cmd_rd0_fire = (state == st_rd_cmd0) ;
wire cmd_rd1_fire = (state == st_rd_cmd1);
wire rx_pop_lo    = (state == st_rd_pop0) && !rxempty;
wire rx_pop_hi    = (state == st_rd_pop1) && !rxempty;

wire [28:0] wr_cmd0 = {1'b1, wr_cmd_valid_halfwords, half_addr0[10:9], half_addr0[23:11], half_addr0[8:0]};
wire [28:0] wr_cmd1 = {1'b1, 4'd1,                  half_addr1[10:9], half_addr1[23:11], half_addr1[8:0]};
wire [28:0] rd_cmd0 = {1'b0, rd_cmd_valid_halfwords, half_addr0[10:9], half_addr0[23:11], half_addr0[8:0]};
wire [28:0] rd_cmd1 = {1'b0, 4'd1,                  half_addr1[10:9], half_addr1[23:11], half_addr1[8:0]};

//____________________State_____________________________________________________
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        state <= st_idle;
    end else begin
        state <= state_n;
    end
end

always @(*) begin
    state_n = state;
    case (state)
        st_idle: begin
            if (mem_wr_req)
                state_n = st_tx_lo;
            else if (mem_rd_req)
                state_n = st_rd_cmd0;
        end
        st_tx_lo: if (!txfull) state_n = st_tx_hi;
        st_tx_hi: if (!txfull) state_n = write_burst_done ? st_wr_wait_fifo : st_wr_ack;
        st_wr_ack: state_n = st_wr_wait_req;
        st_wr_wait_req: begin
            if (mem_wr_req) begin
                if (wr_addr_contig)
                    state_n = st_tx_lo;
                else
                    state_n = st_wr_wait_fifo;
            end else if (mem_rd_req) begin
                state_n = st_wr_wait_fifo;
            end else if (wr_timeout_expired) begin
                state_n = st_wr_wait_fifo;
            end
        end
        st_wr_wait_fifo: if (tx_ready) state_n = st_wr_cmd0;
        st_wr_cmd0: begin
            if (!cmdfull) begin
                if (split_bl1) begin
                    state_n = st_wr_cmd1;
                end else if (wr_deferred_req == wr_defer_write) begin
                    state_n = st_wr_resume_wr;
                end else if (wr_deferred_req == wr_defer_read) begin
                    state_n = st_wr_resume_rd;
                end else begin
                    state_n = st_wr_done;
                end
            end
        end
        st_wr_cmd1: begin
            if (!cmdfull) begin
                if (wr_deferred_req == wr_defer_write)
                    state_n = st_wr_resume_wr;
                else if (wr_deferred_req == wr_defer_read)
                    state_n = st_wr_resume_rd;
                else
                    state_n = st_wr_done;
            end
        end
        st_wr_resume_wr: state_n = st_tx_lo;
        st_wr_resume_rd: state_n = st_rd_cmd0;
        st_wr_done: state_n = st_idle;

        st_rd_cmd0: if (!cmdfull) state_n = split_bl1 ? st_rd_cmd1 : st_rd_wait_fifo;
        st_rd_cmd1: if (!cmdfull) state_n = st_rd_wait_fifo;
        st_rd_wait_fifo: if (rx_ready) state_n = st_rd_pop0;
        st_rd_pop0: if (!rxempty) state_n = st_rd_cap0;
        st_rd_cap0: state_n = st_rd_pop1;
        st_rd_pop1: if (!rxempty) state_n = st_rd_cap1;
        st_rd_cap1: state_n = st_rd_word_done;
        st_rd_word_done: state_n = rd_last_word ? st_idle : st_rd_wait_req;
        st_rd_wait_req: if (mem_rd_req) state_n = st_rd_pop0;
    endcase
end

//____________________Register____________________________________________
// paddr_req
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        paddr_req <= 32'h0;
    else if (start_wr_burst || start_rd_burst)
        paddr_req <= paddr;
end

// wr_word_count
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        wr_word_count <= 3'd0;
    else if (start_wr_burst)
        wr_word_count <= 3'd0;
    else if (tx_push_hi)
        wr_word_count <= wr_word_count + 1'b1;
end

// rd_word_count
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        rd_word_count <= 3'd0;
    else if (start_rd_burst)
        rd_word_count <= 3'd1;
    else if (state == st_rd_word_done && !rd_last_word)
        rd_word_count <= rd_word_count + 1'b1;
end

// deferred request type while flushing a partial burst
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        wr_deferred_req <= wr_defer_none;
    else if ((state == st_wr_wait_req) && mem_wr_req && !wr_addr_contig)
        wr_deferred_req <= wr_defer_write;
    else if ((state == st_wr_wait_req) && mem_rd_req)
        wr_deferred_req <= wr_defer_read;
    else if (start_wr_burst || start_rd_burst || (state == st_wr_done))
        wr_deferred_req <= wr_defer_none;
end

// timeout to flush a trailing partial burst when no more accesses arrive
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        wr_wait_timeout_cnt <= 8'd0;
    else if (!wr_timeout_pending)
        wr_wait_timeout_cnt <= 8'd0;
    else if (wr_wait_timeout_cnt < wr_wait_timeout_cycles)
        wr_wait_timeout_cnt <= wr_wait_timeout_cnt + 1'b1;
end

// rd_lo_data
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        rd_lo_data <= 16'h0;
    else if (state == st_rd_cap0)
        rd_lo_data <= rxrdata;
end

// prdata
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        prdata <= 32'h0;
    else if (state == st_rd_cap1)
        prdata <= {rxrdata, rd_lo_data};
end

//___________Output loguc______________________________________________
assign cmdwe = cmd_wr0_fire | cmd_wr1_fire | cmd_rd0_fire | cmd_rd1_fire;
assign cmdwdata =
    cmd_wr0_fire ? wr_cmd0 :
    cmd_wr1_fire ? wr_cmd1 :
    cmd_rd0_fire ? rd_cmd0 :
    cmd_rd1_fire ? rd_cmd1 :
    29'h0;

assign txwe = tx_push_lo | tx_push_hi;
assign txwdata =
    (state == st_tx_lo) ? pwdata[15:0] :
    (state == st_tx_hi) ? pwdata[31:16] :
    16'h0000;

assign rxre = rx_pop_lo | rx_pop_hi;
assign pready = (state == st_wr_ack) | (state == st_wr_done) | (state == st_rd_word_done);
assign busy = (state != st_idle);

endmodule
