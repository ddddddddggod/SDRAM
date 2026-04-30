`timescale 1ns / 1ps

module sdram_master_ctrl (
    input               clk,
    input               rstb,
    inout  [15:0]       dq,
    input               done,
    // fifo
    input               txempty,
    input               cmdempty,
    input  [15:0]       txrdata,
    input  [28:0]       cmddata,
    input               rxfull,
    input               ref_req,
    input               init_done_ack,
    input               mrs_req,
    input  [12:0]       mrs_val_reg,
    input  [31:0]       timing_reg,
    input               timing_req,
    input               refresh_req,
    input  [15:0]       refresh_reg,

    output              txre,
    output              rxwe,
    output [15:0]       rxwdata,
    output              cmdre,
    // SDRAM
    output reg          cke,
    output reg          cas,
    output reg          ras,
    output reg          we,
    output reg          cs,
    output reg [1:0]    bs,
    output reg [12:0]   addr,
    output reg [1:0]    dqm,
    output              ref_ack,
    output reg          timer_en,
    output reg [15:0]   wait_cnt,
    output              init_done_req,
    output              mrs_req_ack,
    output              timing_req_ack,
    output              refresh_req_ack,
    output [15:0]       refresh_period
);

wire [2:0]  cl;
wire [3:0]  bl;
wire [12:0] mrs_val;
wire [3:0]  tRP;
wire [3:0]  tRCD;
wire [5:0]  tRC;
wire [15:0] init_wait;
wire        start;
reg         init_done;

sdram_master_ctrl_cdc u_ctrl_cdc (
    .clk          (clk),
    .rstb         (rstb),
    .init_done    (init_done),
    .init_done_ack(init_done_ack),
    .mrs_req      (mrs_req),
    .mrs_val_reg  (mrs_val_reg),
    .timing_reg   (timing_reg),
    .timing_req   (timing_req),
    .refresh_req  (refresh_req),
    .refresh_reg  (refresh_reg),
    .init_done_req(init_done_req),
    .mrs_req_ack  (mrs_req_ack),
    .timing_req_ack(timing_req_ack),
    .refresh_req_ack(refresh_req_ack),
    .cl           (cl),
    .bl           (bl),
    .mrs_val      (mrs_val),
    .tRP          (tRP),
    .tRC          (tRC),
    .tRCD         (tRCD),
    .init_wait    (init_wait),
    .start        (start),
    .refresh_period(refresh_period)
);

localparam tRSC = 2;
localparam tWR  = 2;

// ------------------------------------------------------------------
// State
// ------------------------------------------------------------------
localparam [3:0] st_start               = 4'd0;
localparam [3:0] st_init_wait           = 4'd1;
localparam [3:0] st_init_precharge_all  = 4'd2;
localparam [3:0] st_init_refresh        = 4'd3;
localparam [3:0] st_init_mrs            = 4'd4;
localparam [3:0] st_idle                = 4'd5;
localparam [3:0] st_refresh             = 4'd6;
localparam [3:0] st_active              = 4'd7;
localparam [3:0] st_read                = 4'd8;
localparam [3:0] st_r_burst             = 4'd9;
localparam [3:0] st_write               = 4'd10;
localparam [3:0] st_write_mask          = 4'd11;
localparam [3:0] st_w_wait              = 4'd12;
localparam [3:0] st_bank_precharge      = 4'd13;

reg [3:0] state;
reg [3:0] state_n;
reg [3:0] state_d;

// ------------------------------------------------------------------
// Command decode
// ------------------------------------------------------------------
wire        cmd_we_in         = cmddata[28];
wire [3:0]  cmd_valid_half_in = cmddata[27:24];
wire [1:0]  row_bs_in         = cmddata[23:22];
wire [12:0] row_addr_in       = cmddata[21:9];
wire [8:0]  col_addr_in       = cmddata[8:0];
wire        bl_valid          = (bl != 4'd0);
wire        cmd_accept        = (state == st_idle) && !ref_req && !cmdempty;

reg         cmd_we_r;
reg [3:0]   cmd_valid_half_r;
reg [1:0]   row_bs_r;
reg [12:0]  row_addr_r;
reg [8:0]   col_addr_r;


always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        cmd_we_r   <= 1'b0;
        cmd_valid_half_r <= 4'd0;
        row_bs_r   <= 2'b00;
        row_addr_r <= 13'h0000;
        col_addr_r <= 9'h000;
    end else if (cmd_accept) begin
        cmd_we_r   <= cmd_we_in;
        cmd_valid_half_r <= cmd_valid_half_in;
        row_bs_r   <= row_bs_in;
        row_addr_r <= row_addr_in;
        col_addr_r <= col_addr_in;
    end
end

// ------------------------------------------------------------------
// Current-state logic
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        state <= st_start;
    end else begin
        state <= state_n;
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        state_d <= st_start;
    end else begin
        state_d <= state;
    end
end

wire state_enter = (state != state_d);

// ------------------------------------------------------------------
// Init refresh counter
// ------------------------------------------------------------------
reg  [3:0] refresh_cnt;
wire init_refresh_done  = (refresh_cnt == 4'd8);
wire issue_init_refresh = (state == st_init_refresh) && !init_refresh_done && (state_enter || done);

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        refresh_cnt <= 4'd0;
    end else if (issue_init_refresh) begin
        refresh_cnt <= refresh_cnt + 1'b1;
    end
end

// ------------------------------------------------------------------
// Burst counter
// ------------------------------------------------------------------
reg [2:0] burst_cnt;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        burst_cnt <= 3'd0;
    end else if ((state == st_write) || (state == st_write_mask) || (state == st_r_burst)) begin
        burst_cnt <= burst_cnt + 1'b1;
    end else begin
        burst_cnt <= 3'd0;
    end
end

wire [3:0] write_valid_halfwords = (cmd_valid_half_r == 4'd0) ? bl : cmd_valid_half_r;
wire burst_done = ({1'b0, burst_cnt} == (bl - 1'b1));
wire partial_write_burst = cmd_we_r && bl_valid && (write_valid_halfwords < bl);
wire last_valid_write_beat = ({1'b0, burst_cnt} == (write_valid_halfwords - 4'd1));
wire first_valid_write = cmd_we_r && bl_valid && (write_valid_halfwords != 4'd0);
wire more_valid_write  = (state == st_write) && bl_valid && (({1'b0, burst_cnt} + 4'd1) < write_valid_halfwords);
wire first_valid_read  = bl_valid;
wire more_valid_read   = (state == st_r_burst) && bl_valid && (burst_cnt < (bl - 1'b1));

// ------------------------------------------------------------------
// Next-state logic
// ------------------------------------------------------------------
always @(*) begin
    state_n = state;
    case (state)
        st_start: if (start) state_n = st_init_wait;
        st_init_wait: if (done) state_n = st_init_precharge_all;
        st_init_precharge_all: if (done) state_n = st_init_refresh;
        st_init_refresh: if (done && init_refresh_done) state_n = st_init_mrs;
        st_init_mrs: if (done) state_n = st_idle;
        st_idle: begin
            if (ref_req) begin
                state_n = st_refresh;
            end else if (!cmdempty) begin
                state_n = st_active;
            end
        end
        st_refresh: if (done) state_n = st_idle;
        st_active: if (done)  state_n = cmd_we_r ? st_write : st_read;
        st_read: if (done) state_n = st_r_burst;
        st_r_burst: if (burst_done) state_n = st_bank_precharge;
        st_write: begin
            if (burst_done)
                state_n = st_w_wait;
            else if (partial_write_burst && last_valid_write_beat)
                state_n = st_write_mask;
        end
        st_write_mask: if (burst_done) state_n = st_w_wait;
        st_w_wait: if (done) state_n = st_bank_precharge;
        st_bank_precharge: if (done) state_n = st_idle;
    endcase
end

// ------------------------------------------------------------------
// FIFO handshakes
// ------------------------------------------------------------------
assign cmdre   = cmd_accept;
assign ref_ack = (state == st_refresh) && done;

wire first_read = (state == st_read) && done && first_valid_read;
wire seq_read = more_valid_read;
assign rxwe    = !rxfull && (first_read || seq_read);

wire dq_oe = (state == st_write) || (state == st_write_mask);
assign dq  = dq_oe ? ((state == st_write_mask) ? 16'h0000 : txrdata) : 16'hzzzz;
assign rxwdata = dq;

wire first_write = (state == st_active) && done && first_valid_write;
assign txre = !txempty && (first_write || more_valid_write);

// ------------------------------------------------------------------
// Init done pulse
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        init_done <= 1'b0;
    end else if ((state == st_init_mrs) && done) begin
        init_done <= 1'b1;
    end
end

// ------------------------------------------------------------------
// DQ bus control
// ------------------------------------------------------------------
always @(*) begin
    timer_en = 1'b0;
    wait_cnt = 16'h0000;
    cs       = 1'b0;
    ras      = 1'b1;
    cas      = 1'b1;
    we       = 1'b1;
    bs       = row_bs_r;
    addr     = 13'h0000;
    dqm      = 2'b00;
    cke      = 1'b1;

    case (state)
        st_start: begin
            cs  = 1'b1;
            ras = 1'b1;
            cas = 1'b1;
            we  = 1'b1;
            dqm = 2'b11;
        end
        st_init_wait: begin
            timer_en = 1'b1;
            wait_cnt = init_wait;
            cs       = 1'b1;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            dqm      = 2'b11;
        end
        st_init_precharge_all: begin
            timer_en = 1'b1;
            wait_cnt = tRP;
            cs       = 1'b0;
            ras      = state_enter ? 1'b0 : 1'b1;
            cas      = 1'b1;
            we       = state_enter ? 1'b0 : 1'b1;
            addr     = state_enter ? 13'h0400 : 13'h0000;
        end
        st_init_refresh: begin
            timer_en = 1'b1;
            wait_cnt = tRC;
            cs       = 1'b0;
            ras      = issue_init_refresh ? 1'b0 : 1'b1;
            cas      = issue_init_refresh ? 1'b0 : 1'b1;
            we       = 1'b1;
        end
        st_init_mrs: begin
            timer_en = 1'b1;
            wait_cnt = tRSC;
            cs       = 1'b0;
            ras      = state_enter ? 1'b0 : 1'b1;
            cas      = state_enter ? 1'b0 : 1'b1;
            we       = state_enter ? 1'b0 : 1'b1;
            bs       = 2'b00;
            addr     = state_enter ? mrs_val : 13'h0000;
        end
        st_idle: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            timer_en = 1'b0;
            bs       = 2'b00;
            addr     = 13'h0000;
        end
        st_active: begin
            cs       = 1'b0;
            ras      = state_enter ? 1'b0 : 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            timer_en = 1'b1;
            wait_cnt = tRCD;
            bs       = row_bs_r;
            addr     = state_enter ? row_addr_r : 13'h0000;
        end
        st_read: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = state_enter ? 1'b0 : 1'b1;
            we       = 1'b1;
            timer_en = 1'b1;
            wait_cnt = cl;
            bs       = row_bs_r;
            addr     = state_enter ? {4'b0000, col_addr_r} : 13'h0000;
        end
        st_r_burst: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            timer_en = 1'b0;
            wait_cnt = 16'h0000;
            bs       = row_bs_r;
            addr     = 13'h0000;
        end
        st_write: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = (burst_cnt == 0) ? 1'b0 : 1'b1;
            we       = (burst_cnt == 0) ? 1'b0 : 1'b1;
            timer_en = 1'b0;
            wait_cnt = 16'h0000;
            bs       = row_bs_r;
            addr     = (burst_cnt == 0) ? {4'b0000, col_addr_r} : 13'h0000;
            dqm      = 2'b00;
        end
        st_write_mask: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            timer_en = 1'b0;
            wait_cnt = 16'h0000;
            bs       = row_bs_r;
            addr     = 13'h0000;
            dqm      = 2'b11;
        end
        st_w_wait: begin
            cs       = 1'b0;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            timer_en = 1'b1;
            wait_cnt = tWR;
            bs       = row_bs_r;
            addr     = 13'h0000;
        end
        st_bank_precharge: begin
            cs       = 1'b0;
            ras      = state_enter ? 1'b0 : 1'b1;
            cas      = 1'b1;
            we       = state_enter ? 1'b0 : 1'b1;
            timer_en = 1'b1;
            wait_cnt = tRP;
            addr     = 13'h0000;
            bs       = row_bs_r;
        end
        st_refresh: begin
            cs       = 1'b0;
            ras      = state_enter ? 1'b0 : 1'b1;
            cas      = state_enter ? 1'b0 : 1'b1;
            we       = 1'b1;
            timer_en = 1'b1;
            wait_cnt = tRC;
        end
        default: begin
            cs       = 1'b1;
            ras      = 1'b1;
            cas      = 1'b1;
            we       = 1'b1;
            bs       = 2'b00;
            addr     = 13'h0000;
            timer_en = 1'b0;
            wait_cnt = 16'h0000;
            dqm      = 2'b00;
        end
    endcase
end

endmodule
