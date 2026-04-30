`timescale 1ns / 1ps

module sdram_slave_cdc (
    input clk,
    input rstb,
    input pready,
    input pready_ack,
    input pena_req,
    input pwrite_req,
    input psel_req,
    input [31:0] pwdata,
    input [31:0] paddr,

    output pready_req,
    output pena_cdc,
    output pwrite_cdc,
    output psel_cdc,
    output reg [31:0] pwdata_cdc,
    output reg [31:0] paddr_cdc
);

reg [1:0] pready_ack_o;
reg [1:0] pena_req_r;
reg [1:0] pwrite_req_r;
reg [1:0] psel_req_r;
reg pready_r;
reg pena_apb_r, pwrite_apb_r, psel_apb_r;
wire psel_signal;

//-------pready----------------------
wire pready_ack_r;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pready_ack_o <= 2'b00;
    end else begin
        pready_ack_o <= {pready_ack_o[0], pready_ack};
    end
end
assign pready_ack_r = pready_ack_o[1];

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pready_r <= 1'b0;
    end else if (pready_ack_r) begin
        pready_r <= 1'b0;
    end else if (pready) begin
        pready_r <= 1'b1;
    end
end
assign pready_req = pready_r;

//------pena------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pena_req_r <= 2'b00;
    end else begin
        pena_req_r <= {pena_req_r[0], pena_req};
    end
end

assign pena_signal = pena_req_r[0] & ~pena_req_r[1];


always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pena_apb_r   <= 1'b0;
    end else if (pready) begin
        pena_apb_r   <= 1'b0;
    end else if (pena_signal) begin
        pena_apb_r <= 1'b1;
    end
end
assign pena_cdc = pena_apb_r;

//----------pwrite-----------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pwrite_req_r <= 2'b00;
    end else begin
        pwrite_req_r <= {pwrite_req_r[0], pwrite_req};
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pwrite_apb_r <= 1'b0;
    end else if (pready) begin
        pwrite_apb_r <= 1'b0;
    end else if (psel_signal) begin
        pwrite_apb_r <= pwrite_req_r[0];
    end
end
assign pwrite_cdc = pwrite_apb_r;


//-----------------psel-----------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        psel_req_r <= 2'b00;
    end else begin
        psel_req_r <= {psel_req_r[0], psel_req};
    end
end
assign psel_signal = psel_req_r[0] & ~psel_req_r[1];

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        psel_apb_r   <= 1'b0;
    end else if (pready) begin
        psel_apb_r   <= 1'b0;
    end else if (psel_signal) begin
        psel_apb_r <= 1'b1;
    end
end
assign psel_cdc = psel_apb_r;

//-------paddr,pwdata------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pwdata_cdc <= 32'h0;
        paddr_cdc  <= 32'h0;
    end else if (psel_signal) begin
        pwdata_cdc <= pwdata;
        paddr_cdc  <= paddr;
    end
end

endmodule
