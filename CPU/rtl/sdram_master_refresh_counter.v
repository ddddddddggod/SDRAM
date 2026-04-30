`timescale 1ns / 1ps

module sdram_master_refresh_counter (
    input      clk,
    input      rstb,
    input [15:0] refresh_period,

    input      ref_ack,  
    output reg ref_req    
);

reg [15:0] cnt;
reg [15:0] refresh_period_d;
wire refresh_cfg_valid = (refresh_period != 16'h0000);
wire cnt_max = refresh_cfg_valid && (cnt == (refresh_period - 16'd1));
wire refresh_cfg_changed = (refresh_period != refresh_period_d);

always @(posedge clk or negedge rstb) begin
    if (!rstb)
        refresh_period_d <= 16'h0000;
    else
        refresh_period_d <= refresh_period;
end

// counter
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        cnt <= 16'h0000;
    else if (!refresh_cfg_valid)
        cnt <= 16'h0000;
    else if (refresh_cfg_changed)
        cnt <= 16'h0000;
    else if (ref_ack)
        cnt <= 16'h0000;   
    else if (cnt_max)
        cnt <= 16'h0000;
    else
        cnt <= cnt + 16'd1;
end

// ref_req
always @(posedge clk or negedge rstb) begin
    if (!rstb)
        ref_req <= 1'b0;
    else if (!refresh_cfg_valid)
        ref_req <= 1'b0;
    else if (refresh_cfg_changed)
        ref_req <= 1'b0;
    else if (ref_ack)
        ref_req <= 1'b0; 
    else if (cnt_max)
        ref_req <= 1'b1;  
end

endmodule
