`timescale 1ns / 1ps

module sdram_apb_master (
    input             clk,
    input             rstb,
    input             pready,
    input      [31:0] prdata,
    input      [31:0] rfwdata,

    input             we,
    input      [31:0] mem_addr,
    input      [6:0]  rf_addr_base,
    input      [12:0] mrs_val,
    input      [15:0] init_wait,
    input      [5:0]  tRC,
    input      [3:0]  tRCD,
    input      [3:0]  tRP,
    input      [15:0] refresh_period,
    input             start,

    // APB Master -> Slave
    output wire [31:0] paddr,
    output wire        pwrite,
    output wire        pena,
    output wire        psel,
    output wire [31:0]  pwdata,

    // pkt_ctrl
    output wire        rdy,
    output wire        request,
    output wire        init,
    output wire        done,
    output wire        op_start,
    output wire [31:0] rfrdata
);

wire rw_valid;
wire init_i;
wire [39:0] cmd_tuple = {we, mem_addr, rf_addr_base};

reg [39:0] cmd_shadow;
reg        cmd_pending;
reg        init_seen;

// Treat command-field updates from firmware as a one-shot request pulse.
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        cmd_shadow  <= 40'h0;
        cmd_pending <= 1'b0;
        init_seen   <= 1'b0;
    end else if (!init_i) begin
        cmd_shadow  <= cmd_tuple;
        cmd_pending <= 1'b0;
        init_seen   <= 1'b0;
    end else if (!init_seen) begin
        cmd_shadow  <= cmd_tuple;
        cmd_pending <= 1'b0;
        init_seen   <= 1'b1;
    end else begin
        if (cmd_tuple != cmd_shadow) begin
            cmd_shadow  <= cmd_tuple;
            cmd_pending <= 1'b1;
        end else if (op_start) begin
            cmd_pending <= 1'b0;
        end
    end
end

assign op_start = init_seen && cmd_pending && !rw_valid;
assign init     = init_i;

sdram_apb_master_ctrl u_apb_master_ctrl(
	.clk  		(clk),
	.rstb 		(rstb),
	.pready 	(pready),
	.rw_valid 	(rw_valid),
	
	.psel 		(psel),
	.pena 		(pena)
	);

sdram_apb_master_rw u_apb_master_rw(
	.clk 		(clk),
	.rstb 		(rstb),
	.pready 	(pready),
	.prdata     (prdata),
	.rfwdata 	(rfwdata),

	.op_start   (op_start),
	.we 		(we),
	.mem_addr 	(mem_addr),
	.mrs_val 	(mrs_val),
	.init_wait  (init_wait),
	.tRC 		(tRC),
	.tRCD 		(tRCD),
	.tRP 		(tRP),
	.refresh_period(refresh_period),
	.start 		(start),

	.paddr 		(paddr),
	.pwrite 	(pwrite),
	.pwdata 	(pwdata),
	.rdy 		(rdy),
	.request 	(request),
	.init       (init_i),
	.done       (done),
	.rfrdata 	(rfrdata),
	.rw_valid 	(rw_valid)
);



endmodule
