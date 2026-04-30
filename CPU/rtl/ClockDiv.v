`timescale 1ns / 1ps

module ClockDiv (
    input  wire CLK_I,
    output reg  CLK_O
);

initial CLK_O = 1'b0;

always @(posedge CLK_I) begin
    CLK_O <= ~CLK_O;
end

endmodule
