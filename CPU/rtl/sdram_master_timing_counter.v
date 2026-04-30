`timescale 1ns / 1ps

module sdram_master_timing_counter (
    input        clk,
    input        rstb,
    input        timer_en,
    input [15:0] wait_cnt,
    output       done
);

reg [15:0] cnt;
reg [15:0] wait_cnt_q;

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        wait_cnt_q <= 16'h0;
    end else if (!timer_en) begin
        wait_cnt_q <= 16'h0;
    end else begin
        wait_cnt_q <= wait_cnt;
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        cnt <= 16'h0;
    end else if (!timer_en) begin
        cnt <= 16'h0;
    end else if (wait_cnt != wait_cnt_q || cnt == 16'h0) begin
        cnt <= wait_cnt;
    end else begin
        cnt <= cnt - 1;
    end
end

assign done = timer_en && (cnt == 16'h1);

endmodule
