`timescale 1ns / 1ps

module sdram_rf (
    input         clk,
    input         rstb, 
    input         we,
    input  [6:0]  addr,
    input  [31:0] rfrdata,   
    output [31:0] rfwdata
);
    reg [15:0] mem [0:127];  // 128x16bit
    wire [6:0] addr_hi = addr + 7'd1;

    integer i;
    always @(posedge clk or negedge rstb) begin
        if (!rstb) begin
            for (i=0; i<128; i=i+1) 
                mem[i] <= 16'h0;  // 8'h00 → 32'h0
        end else if (we) begin
            mem[addr]    <= rfrdata[15:0];
            mem[addr_hi] <= rfrdata[31:16];
        end
    end

    assign rfwdata = {mem[addr_hi], mem[addr]};

endmodule
