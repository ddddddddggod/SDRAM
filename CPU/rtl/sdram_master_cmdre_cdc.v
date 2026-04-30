`timescale 1ns / 1ps

module sdram_master_cmdre_cdc (
    input               clk,
    input               rstb,
    input               cmdwe_req,
    input      [28:0]   cmdwdata_r,
    input               cmdre,

    output reg [28:0]   cmdrdata_cdc,
    output reg          cmdwe_ack,
    output reg          cmd_present
);

reg [1:0] cmdwe_req_r;

wire cmdwe_signal = cmdwe_req_r[0] & ~cmdwe_req_r[1];

// ------------------------------------------------------------------
// cmdwe_req sync (clk1 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdwe_req_r <= 2'b00;
    else
        cmdwe_req_r <= {cmdwe_req_r[0], cmdwe_req};
end

// ------------------------------------------------------------------
// cmdrdata_cdc (clk1 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdrdata_cdc <= 29'h0;
    else if (cmdwe_signal)
        cmdrdata_cdc <= cmdwdata_r;
end

// ------------------------------------------------------------------
// cmdwe_ack (clk1 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmdwe_ack <= 1'b0;
    else if (!cmdwe_req_r[1])
        cmdwe_ack <= 1'b0;
    else if (cmdre)
        cmdwe_ack <= 1'b1;
end

// ------------------------------------------------------------------
// cmd_present (clk1 domain)
// ------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cmd_present <= 1'b0;
    else if (cmdwe_signal)
        cmd_present <= 1'b1;
    else if (cmdre)
        cmd_present <= 1'b0;
end

endmodule
