`timescale 1ns / 1ps

module sdram_pkt_ctrl (
    input op_start,
    input rdy,
    input request,

    output we,
    output load_addr,
    output inc_addr
);

assign we        = rdy;
assign load_addr = op_start;
assign inc_addr  = rdy || request;

endmodule
