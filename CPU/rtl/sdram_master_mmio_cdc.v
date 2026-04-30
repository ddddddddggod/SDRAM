`timescale 1ns / 1ps

module sdram_master_mmio_cdc (
    input       clk,
    input       rstb,
    input       init_done_req,
    input       mrs_req_ack,
    input       m_valid,
    input       tm_valid,
    input       timing_req_ack,
    input       rf_valid,
    input       refresh_req_ack,

    output      init_done_ack,
    output      init_done_signal,
    output      mrs_req,
    output      timing_req,
    output      refresh_req
);

// ------------------------------------------------------------------
// init_done pulse crossing back into the APB/MMIO clock domain
// ------------------------------------------------------------------
reg [1:0] init_done_req_sync;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        init_done_req_sync <= 2'b00;
    end else begin
        init_done_req_sync <= {init_done_req_sync[0], init_done_req};
    end
end

assign init_done_ack    = init_done_req_sync[1];
assign init_done_signal = init_done_req_sync[0] & ~init_done_req_sync[1];

// ------------------------------------------------------------------
// MRS request handshake
// ------------------------------------------------------------------
reg [1:0] mrs_req_ack_sync;
reg       mrs_req_r;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        mrs_req_ack_sync <= 2'b00;
    end else begin
        mrs_req_ack_sync <= {mrs_req_ack_sync[0], mrs_req_ack};
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        mrs_req_r <= 1'b0;
    end else if (mrs_req_ack_sync[1]) begin
        mrs_req_r <= 1'b0;
    end else if (m_valid) begin
        mrs_req_r <= 1'b1;
    end
end

assign mrs_req = mrs_req_r;

// ------------------------------------------------------------------
// Timing/start request handshake
// ------------------------------------------------------------------
reg [1:0] timing_req_ack_sync;
reg       timing_req_r;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        timing_req_ack_sync <= 2'b00;
    end else begin
        timing_req_ack_sync <= {timing_req_ack_sync[0], timing_req_ack};
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        timing_req_r <= 1'b0;
    end else if (timing_req_ack_sync[1]) begin
        timing_req_r <= 1'b0;
    end else if (tm_valid) begin
        timing_req_r <= 1'b1;
    end
end

assign timing_req = timing_req_r;

// ------------------------------------------------------------------
// Refresh period request handshake
// ------------------------------------------------------------------
reg [1:0] refresh_req_ack_sync;
reg       refresh_req_r;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        refresh_req_ack_sync <= 2'b00;
    end else begin
        refresh_req_ack_sync <= {refresh_req_ack_sync[0], refresh_req_ack};
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        refresh_req_r <= 1'b0;
    end else if (refresh_req_ack_sync[1]) begin
        refresh_req_r <= 1'b0;
    end else if (rf_valid) begin
        refresh_req_r <= 1'b1;
    end
end

assign refresh_req = refresh_req_r;

endmodule
