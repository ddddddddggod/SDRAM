`timescale 1ns / 1ps

module sdram_apb_master_rw (
    input             clk,
    input             rstb,
    input             pready,
    input      [31:0] prdata,
    input      [31:0] rfwdata,

    input             op_start,
    input             we,
    input      [31:0] mem_addr,
    input      [12:0] mrs_val,
    input      [15:0] init_wait,
    input      [5:0]  tRC,
    input      [3:0]  tRCD,
    input      [3:0]  tRP,
    input      [15:0] refresh_period,
    input             start,

    output reg [31:0] paddr,
    output reg        pwrite,
    output reg [31:0] pwdata,
    output reg        rdy,
    output reg        request,
    output reg        init,
    output reg        done,
    output reg [31:0] rfrdata,
    output            rw_valid
);

localparam [3:0] m_wait_start = 4'd0;
localparam [3:0] m_ini_mrs    = 4'd1;
localparam [3:0] m_init_refresh= 4'd2;
localparam [3:0] m_init_timing = 4'd3;
localparam [3:0] m_poll_init  = 4'd4;
localparam [3:0] m_idle       = 4'd5;
localparam [3:0] m_status     = 4'd6;
localparam [3:0] m_write      = 4'd7;
localparam [3:0] m_read       = 4'd8;

localparam [31:0] mrs_val_addr = 32'h5000_0000;
localparam [31:0] timing_addr  = 32'h5000_0004;
localparam [31:0] refresh_addr = 32'h5000_0008;
localparam [31:0] status_addr  = 32'h5000_0010;


reg [3:0]  m_state, m_state_n;
reg [31:0] op_mem_addr;
reg [3:0]  beat_idx;
reg        op_we;
reg        req_pending;


wire status_busy = prdata[1];
wire status_init_done = prdata[0];
wire [31:0] beat_addr = op_mem_addr + {26'd0, beat_idx, 2'b00};

wire [3:0] req_burst_len = 
(mrs_val[2:0] == 3'b000) ? 4'd1 :
(mrs_val[2:0] == 3'b001) ? 4'd2 :
(mrs_val[2:0] == 3'b010) ? 4'd4 :
(mrs_val[2:0] == 3'b011) ? 4'd8 : 4'd0;
wire [3:0] req_word_len =
    (req_burst_len == 4'd1) ? 4'd1 : {1'b0, req_burst_len[3:1]};
wire burst_done = (beat_idx == (req_word_len - 1'b1));


always @(posedge clk or negedge rstb) begin
    if (!rstb)
        m_state <= m_wait_start;
    else
        m_state <= m_state_n;
end

always @(*) begin
    m_state_n = m_state;
    case (m_state)
        m_wait_start: if (start) m_state_n = m_ini_mrs;
        m_ini_mrs:     if (pready) m_state_n = m_init_refresh;
        m_init_refresh: if (pready) m_state_n = m_init_timing;
        m_init_timing:  if (pready) m_state_n = m_poll_init;
        m_poll_init:   if (pready && status_init_done) m_state_n = m_idle;
        m_idle: if (op_start) m_state_n = m_status;
        m_status: if (pready && req_pending && !status_busy)
                      m_state_n = op_we ? m_write : m_read;
        m_write: if (pready && burst_done) m_state_n = m_idle;
        m_read:  if (pready && burst_done) m_state_n = m_idle;
        default: m_state_n = m_wait_start;
    endcase
end

//burst counter
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        beat_idx <= 4'd0;
    else if ((m_state == m_idle) && op_start)
        beat_idx <= 4'd0;
    else if (((m_state == m_write) || (m_state == m_read)) && pready && !burst_done)
        beat_idx <= beat_idx + 1'b1;
end

//first sdram address
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        op_mem_addr <= 32'h0;
    end else if ((m_state == m_idle) && op_start) begin
        op_mem_addr <= mem_addr;
    end
end


// we start signal
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        op_we <= 1'b0;
    else if ((m_state == m_idle) && op_start)
        op_we <= we;
end

//delay
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        req_pending <= 1'b0;
    else if ((m_state == m_idle) && op_start)
        req_pending <= 1'b1;
    else if ((m_state == m_status) && pready && !status_busy)
        req_pending <= 1'b0;
end


//__________Output logic____________________________
//init
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        init <= 1'b0;
    else if ((m_state == m_poll_init) && pready && status_init_done)
        init <= 1'b1;
end


//rfrdata
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        rfrdata <= 32'h0000_0000;
    else if ((m_state == m_read) && pready)
        rfrdata <= prdata;
end

//request
always @(posedge clk or negedge rstb) begin
    if (!rstb) request <= 1'b0;
    else       request <= (m_state == m_write) && pready;
end

//rdy
always @(posedge clk or negedge rstb) begin
    if (!rstb) rdy <= 1'b0;
    else       rdy <= (m_state == m_read) && pready;
end

//done
always @(posedge clk or negedge rstb) begin
    if (!rstb) done <= 1'b0;
    else       done <= pready && burst_done && ((m_state == m_write) || (m_state == m_read));
end


//start register
reg start_hold;
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        start_hold <= 1'b0;
    else if (start)
        start_hold <= 1'b1;
end

assign rw_valid = (m_state != m_wait_start) && (m_state != m_idle);

always @(*) begin
    paddr  = 32'h0;
    pwrite = 1'b0;
    pwdata = 32'h0;

    case (m_state)
        m_ini_mrs: begin
            paddr  = mrs_val_addr;
            pwrite = 1'b1;
            pwdata = {19'h0, mrs_val};
        end
        m_init_refresh: begin
            paddr  = refresh_addr;
            pwrite = 1'b1;
            pwdata = {16'h0, refresh_period};
        end
        m_init_timing: begin
            paddr  = timing_addr;
            pwrite = 1'b1;
            pwdata = {1'b0, start_hold, tRP, tRCD, tRC, init_wait};
        end
        m_poll_init: begin
            paddr  = status_addr;
            pwrite = 1'b0;
        end
        m_status: begin
            paddr = status_addr;
            pwrite = 1'b0;
            pwdata = 32'h0;
        end
        m_write: begin
            paddr  = beat_addr;
            pwrite = 1'b1;
            pwdata = rfwdata;
        end
        m_read: begin
            paddr  = beat_addr;
            pwrite = 1'b0;
        end
        default: begin
            paddr  = 32'h0;
            pwrite = 1'b0;
            pwdata = 32'h0;
        end
    endcase
end

endmodule
