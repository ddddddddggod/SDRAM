`timescale 1ns / 1ps

module sdram_master_ctrl_cdc (
    input               clk,
    input               rstb,
    input               init_done,
    input               init_done_ack,
    input               mrs_req,
    input      [12:0]   mrs_val_reg,
    input      [31:0]   timing_reg,
    input               timing_req,
    input               refresh_req,
    input      [15:0]   refresh_reg,

    output              init_done_req,
    output              mrs_req_ack,
    output              timing_req_ack,
    output              refresh_req_ack,
    output reg [2:0]    cl,
    output reg [3:0]    bl,
    output reg [12:0]   mrs_val,
    output reg [3:0]    tRP,
    output reg [3:0]    tRCD,
    output reg [5:0]    tRC,
    output reg [15:0]   init_wait,
    output reg          start,
    output reg [15:0]   refresh_period
);

wire [3:0] bl_mux =
    (mrs_val_reg[2:0] == 3'b000) ? 4'd1 :
    (mrs_val_reg[2:0] == 3'b001) ? 4'd2 :
    (mrs_val_reg[2:0] == 3'b010) ? 4'd4 :
    (mrs_val_reg[2:0] == 3'b011) ? 4'd8 : 4'd0;

wire [2:0] cl_mux =
    (mrs_val_reg[6:4] == 3'b010) ? 3'd2 :
    (mrs_val_reg[6:4] == 3'b011) ? 3'd3 : 3'd0;

// ------------------------------------------------------------------
// init_done handshake back into the APB/MMIO clock domain
// ------------------------------------------------------------------
reg [1:0] init_done_ack_sync;
reg       init_done_req_r;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        init_done_ack_sync <= 2'b00;
    end else begin
        init_done_ack_sync <= {init_done_ack_sync[0], init_done_ack};
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        init_done_req_r <= 1'b0;
    end else if (init_done_ack_sync[1]) begin
        init_done_req_r <= 1'b0;
    end else if (init_done) begin
        init_done_req_r <= 1'b1;
    end
end

assign init_done_req = init_done_req_r;

// ------------------------------------------------------------------
// MRS request crossing into the SDRAM clock domain
// ------------------------------------------------------------------
reg [1:0] mrs_req_sync;
wire      mrs_req_signal;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        mrs_req_sync <= 2'b00;
    end else begin
        mrs_req_sync <= {mrs_req_sync[0], mrs_req};
    end
end

assign mrs_req_ack    = mrs_req_sync[1];
assign mrs_req_signal = mrs_req_sync[0] & ~mrs_req_sync[1];

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        mrs_val <= 13'h000;
        cl      <= 3'd0;
        bl      <= 4'd0;
    end else if (mrs_req_signal) begin
        mrs_val <= mrs_val_reg;
        cl      <= cl_mux;
        bl      <= bl_mux;
    end
end

// ------------------------------------------------------------------
// Timing/start request crossing into the SDRAM clock domain
// ------------------------------------------------------------------
reg [1:0] timing_req_sync;
wire      timing_req_signal;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        timing_req_sync <= 2'b00;
    end else begin
        timing_req_sync <= {timing_req_sync[0], timing_req};
    end
end

assign timing_req_ack    = timing_req_sync[1];
assign timing_req_signal = timing_req_sync[0] & ~timing_req_sync[1];

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        tRP       <= 4'd0;
        tRCD      <= 4'd0;
        tRC       <= 6'd0;
        init_wait <= 16'd0;
        start     <= 1'b0;
    end else if (timing_req_signal) begin
        init_wait <= timing_reg[15:0];
        tRC       <= timing_reg[21:16];
        tRCD      <= timing_reg[25:22];
        tRP       <= timing_reg[29:26];
        start     <= timing_reg[30];
    end
end

// ------------------------------------------------------------------
// Refresh-period request crossing into the SDRAM clock domain
// ------------------------------------------------------------------
reg [1:0] refresh_req_sync;
wire      refresh_req_signal;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        refresh_req_sync <= 2'b00;
    end else begin
        refresh_req_sync <= {refresh_req_sync[0], refresh_req};
    end
end

assign refresh_req_ack    = refresh_req_sync[1];
assign refresh_req_signal = refresh_req_sync[0] & ~refresh_req_sync[1];

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        refresh_period <= 16'h0000;
    end else if (refresh_req_signal) begin
        refresh_period <= refresh_reg;
    end
end

endmodule
