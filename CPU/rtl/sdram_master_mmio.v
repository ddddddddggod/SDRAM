`timescale 1ns / 1ps
module sdram_master_mmio (
    input               clk,
    input               rstb,
    input               init_done_req,
    input      [31:0]   paddr,
    input      [31:0]   pwdata,
    input               tm_valid,
    input               rf_valid,
    input               busy,
    input               rxempty,
    input               txfull,
    input               mrs_valid,
    input               mrs_req_ack,
    input               timing_req_ack,
    input               refresh_req_ack,

    output reg [31:0]   prdata,
    output              init_done_ack,
    output reg [12:0]   mrs_val_reg,
    output reg [31:0]   timing_reg,
    output              mrs_req,
    output reg [15:0]   refresh_reg,
    output              timing_req,
    output              refresh_req
);

localparam [31:0] mrs_val_addr = 32'h5000_0000;
localparam [31:0] timing_addr  = 32'h5000_0004;
localparam [31:0] refresh_addr = 32'h5000_0008;
localparam [31:0] status_addr  = 32'h5000_0010;

wire init_done_signal;
reg  [31:0] status_reg;

sdram_master_mmio_cdc u_mmio_cdc (
    .clk             (clk),
    .rstb            (rstb),
    .init_done_req   (init_done_req),
    .mrs_req_ack     (mrs_req_ack),
    .m_valid         (mrs_valid),
    .tm_valid        (tm_valid),
    .timing_req_ack  (timing_req_ack),
    .rf_valid        (rf_valid),
    .refresh_req_ack (refresh_req_ack),
    .init_done_ack   (init_done_ack),
    .init_done_signal(init_done_signal),
    .mrs_req         (mrs_req),
    .timing_req      (timing_req),
    .refresh_req     (refresh_req)
);

always @(posedge clk or negedge rstb) begin
    if (!rstb)
        mrs_val_reg <= 13'h000;
    else if (mrs_valid)
        mrs_val_reg <= pwdata[12:0];
end

always @(posedge clk or negedge rstb) begin
    if (!rstb)
        timing_reg <= 32'h0000_0000;
    else if (tm_valid)
        timing_reg <= pwdata;
end

always @(posedge clk or negedge rstb) begin
    if (!rstb)
        refresh_reg <= 16'h0000;
    else if (rf_valid)
        refresh_reg <= pwdata[15:0];
end

reg init_fin;
always @(posedge clk or negedge rstb) begin
    if(~rstb) begin
        init_fin <= 1'b0;
    end else if (init_done_signal) begin
        init_fin <= 1'b1;
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        status_reg <= 32'h0000_0000;
    end else begin
        status_reg[1:0] <= {busy, init_fin};
    end
end

always @(*) begin
    case (paddr)
        mrs_val_addr: prdata = {19'h0, mrs_val_reg};
        timing_addr:  prdata = timing_reg;
        refresh_addr: prdata = {16'h0, refresh_reg};
        status_addr:  prdata = status_reg;
        default:      prdata = 32'h0000_0000;
    endcase
end

endmodule
