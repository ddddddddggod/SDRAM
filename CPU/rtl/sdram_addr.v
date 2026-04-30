`timescale 1ns / 1ps

module sdram_addr (
    input clk,
    input rstb,
    input load_addr,      
    input inc_addr,       
    input [6:0] rf_addr,      
    output reg [6:0] addr 
);
    
    always @(posedge clk or negedge rstb) begin
        if (!rstb) begin
            addr <= 7'd0;
        end else if (load_addr) begin
            addr <= rf_addr;     
        end else if (inc_addr) begin
            addr <= addr + 7'd2; 
        end
    end
endmodule
