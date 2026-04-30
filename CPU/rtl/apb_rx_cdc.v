`timescale 1ns / 1ps

module apb_rx_cdc (
    input clk,
    input rstb,
    input pready_req,
    input pena,
    input pwrite,
    input psel,
    input [31:0] prdata,

    output pready_ack,
    output pready_signal,
    output pena_req,
    output pwrite_req,
    output psel_req,
    output reg [31:0] prdata_cdc
);

//-------------pready----------------------
reg pready_ack_d, pready_ack_dd;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pready_ack_d  <= 1'b0;
        pready_ack_dd <= 1'b0;
    end else begin
        pready_ack_d  <= pready_ack;
        pready_ack_dd <= pready_ack_d;
    end
end

reg [1:0] pready_req_r;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pready_req_r <= 2'b00;
    end else begin
        pready_req_r <= {pready_req_r[0], pready_req};
    end
end
assign pready_ack = pready_req_r[1];
assign pready_signal = pready_ack_d & ~pready_ack_dd;


//----------------pena--------------------------

reg pena_r;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pena_r <= 1'b0;
    end else if (pready_ack) begin
        pena_r <= 1'b0;
    end else if (pena) begin
        pena_r <= 1'b1;
    end
end

assign pena_req = pena_r;

//-----------pwrite---------------------

reg psel_r;
reg pwrite_r;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        pwrite_r <= 1'b0;
    end else if (pready_ack) begin
        pwrite_r <= 1'b0;
    end else if (psel) begin
        pwrite_r <= pwrite;
    end
end

assign pwrite_req = pwrite_r;


//----------------psel------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        psel_r <= 1'b0;
    end else if (pready_ack) begin
        psel_r <= 1'b0;
    end else if (psel) begin
        psel_r <= 1'b1;
    end
end
assign psel_req = psel_r;


//-----------prdata--------------------

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        prdata_cdc <= 32'h0;
    end else if (pready_ack) begin
        prdata_cdc <= prdata;
    end
end

endmodule
