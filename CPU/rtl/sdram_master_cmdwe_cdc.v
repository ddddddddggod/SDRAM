`timescale 1ns / 1ps

module sdram_master_cmdwe_cdc (
    input               clk,
    input               rstb,
    input               cmdwe,
    input               cmdfull,
    input      [28:0]   cmdwdata,
    input               cmdwe_ack,

    output reg [28:0]   cmdwdata_r,
    output reg          cmdwe_req,
    output reg [1:0]    cmdwe_ack_r
);

wire cmdwe_ack_signal = cmdwe_ack_r[0] & ~cmdwe_ack_r[1];

// ------------------------------------------------------------------
// cmdwdata_r (clk2 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdwdata_r <= 29'h0;
    else if (cmdwe && !cmdfull)
        cmdwdata_r <= cmdwdata;
end

// ------------------------------------------------------------------
// cmdwe_req (clk2 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdwe_req <= 1'b0;
    else if (cmdwe_ack_signal)
        cmdwe_req <= 1'b0;
    else if (cmdwe && !cmdfull)
        cmdwe_req <= 1'b1;
end

// ------------------------------------------------------------------
// cmdwe_ack sync (clk2 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdwe_ack_r <= 2'b00;
    else
        cmdwe_ack_r <= {cmdwe_ack_r[0], cmdwe_ack};
end

endmodule
