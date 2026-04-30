`timescale 1ns / 1ps

module sdram_master_top
(
    input           clk1,
    input           clk2,
    input           rstb,
    input           pwrite,
    input  [31:0]   paddr,
    input           pena,
    input           psel,
    input  [31:0]   pwdata,

    output          pready,
    output [31:0]   prdata,
    output          cke,
    output          cs,
    output          ras,
    output          cas,
    output          we,
    output [1:0]    bs,
    output [12:0]   addr,
    output [1:0]    dqm,
    inout  [15:0]   dq
);

// ------------------------------------------------------------------
// Master Ctrl side
// ------------------------------------------------------------------
wire        txempty;
wire        rxfull;
wire        txre;
wire        rxwe;
wire        cmdre;
wire        cmdempty;
wire        cmdfull;
wire [15:0] rxwdata;
wire [15:0] txrdata;
wire        ref_req;
wire        ref_ack;
wire        init_done_ack;
wire        init_done_req;
wire        done;
wire        timer_en;
wire [15:0] wait_cnt;
wire        mrs_req;
wire        mrs_req_ack;
wire [12:0] mrs_val_reg;
wire [31:0] timing_reg;
wire        timing_req;
wire        timing_req_ack;
wire        refresh_req;
wire        refresh_req_ack;
wire [15:0] refresh_reg;
wire [15:0] refresh_period;
wire        cmdwe;
wire [28:0] cmd_data;
wire [28:0] cmdwdata;

sdram_master_ctrl u_ctrl (
    .clk            (clk1),
    .rstb           (rstb),
    .dq             (dq),
    .done           (done),
    .txempty        (txempty),
    .cmdempty       (cmdempty),
    .txrdata        (txrdata),
    .cmddata        (cmd_data),
    .rxfull         (rxfull),
    .ref_req        (ref_req),
    .init_done_ack  (init_done_ack),
    .mrs_req        (mrs_req),
    .mrs_val_reg    (mrs_val_reg),
    .timing_reg     (timing_reg),
    .timing_req     (timing_req),
    .refresh_req    (refresh_req),
    .refresh_reg    (refresh_reg),
    .txre           (txre),
    .rxwe           (rxwe),
    .rxwdata        (rxwdata),
    .cmdre          (cmdre),
    .cke            (cke),
    .cas            (cas),
    .ras            (ras),
    .we             (we),
    .cs             (cs),
    .bs             (bs),
    .addr           (addr),
    .dqm            (dqm),
    .ref_ack        (ref_ack),
    .timer_en       (timer_en),
    .wait_cnt       (wait_cnt),
    .init_done_req  (init_done_req),
    .mrs_req_ack    (mrs_req_ack),
    .timing_req_ack (timing_req_ack),
    .refresh_req_ack(refresh_req_ack),
    .refresh_period (refresh_period)
);

// ------------------------------------------------------------------
// Refresh Counter
// ------------------------------------------------------------------
sdram_master_refresh_counter u_ref_cnt (
    .clk        (clk1),
    .rstb       (rstb),
    .refresh_period(refresh_period),
    .ref_ack    (ref_ack),
    .ref_req    (ref_req)
);

// ------------------------------------------------------------------
// Timing Counter
// ------------------------------------------------------------------
sdram_master_timing_counter u_timing_cnt (
    .clk        (clk1),
    .rstb       (rstb),
    .timer_en   (timer_en),
    .wait_cnt   (wait_cnt),
    .done       (done)
);

// ------------------------------------------------------------------
// CMD CDC mailbox (4-phase req/ack handshake)
// ------------------------------------------------------------------
wire [28:0] cmdwdata_r;
wire [28:0] cmdrdata_cdc;
wire        cmdwe_req;
wire        cmdwe_ack;
wire [1:0]  cmdwe_ack_r;
wire        cmd_present;

sdram_master_cmdwe_cdc u_cmdwe_cdc (
    .clk        (clk2),
    .rstb       (rstb),
    .cmdwe      (cmdwe),
    .cmdfull    (cmdfull),
    .cmdwdata   (cmdwdata),
    .cmdwe_ack  (cmdwe_ack),
    .cmdwdata_r (cmdwdata_r),
    .cmdwe_req  (cmdwe_req),
    .cmdwe_ack_r(cmdwe_ack_r)
);

sdram_master_cmdre_cdc u_cmdre_cdc (
    .clk        (clk1),
    .rstb       (rstb),
    .cmdwe_req  (cmdwe_req),
    .cmdwdata_r (cmdwdata_r),
    .cmdre      (cmdre),
    .cmdrdata_cdc(cmdrdata_cdc),
    .cmdwe_ack  (cmdwe_ack),
    .cmd_present(cmd_present)
);

assign cmd_data = cmdrdata_cdc;
assign cmdempty = !cmd_present;
assign cmdfull  = cmdwe_req || cmdwe_ack_r[1];
// ------------------------------------------------------------------
// RX FIFO
// ------------------------------------------------------------------
wire [15:0] rxrdata;
wire        rxre;
wire [3:0]  rx_diff;
wire        rxempty;

generic_fifo_dc #(
    .dw(16),
    .aw(3)
) u_rx_fifo (
    .wr_clk (clk1),
    .rd_clk (clk2),
    .rst    (rstb),
    .clr    (1'b0),
    .din    (rxwdata),
    .we     (rxwe),
    .dout   (rxrdata),
    .re     (rxre),
    .empty  (rxempty),
    .full   (rxfull),
    .full_n (),
    .empty_n(),
    .level  (),
    .wr_diff(),
    .rd_diff(rx_diff)
);

// ------------------------------------------------------------------
// TX FIFO
// ------------------------------------------------------------------
wire [15:0] txwdata;
wire        txwe;
wire        txfull;
wire [3:0]  tx_diff;

generic_fifo_dc #(
    .dw(16),
    .aw(3)
) u_tx_fifo (
    .wr_clk (clk2),
    .rd_clk (clk1),
    .rst    (rstb),
    .clr    (1'b0),
    .din    (txwdata),
    .we     (txwe),
    .dout   (txrdata),
    .re     (txre),
    .empty  (txempty),
    .full   (txfull),
    .full_n (),
    .empty_n(),
    .level  (),
    .wr_diff(tx_diff),
    .rd_diff()
);

// ------------------------------------------------------------------
// APB Slave
// ------------------------------------------------------------------
wire        mrs_valid;
wire        tm_valid;
wire        rf_valid;
wire        mem_busy_status;
wire [31:0] mem_prdata;
wire [31:0] cfg_prdata;
wire        sdram_prdata_sel;

sdram_master_apb_slave u_apb_slave (
    .clk        (clk2),
    .rstb       (rstb),
    .pwrite     (pwrite),
    .paddr      (paddr),
    .pwdata     (pwdata),
    .pena       (pena),
    .psel       (psel),
    .cmdfull    (cmdfull),
    .txfull     (txfull),
    .tx_diff    (tx_diff),
    .rx_diff    (rx_diff),
    .rxempty    (rxempty),
    .rxrdata    (rxrdata),
    .pready     (pready),
    .mrs_valid  (mrs_valid),
    .tm_valid   (tm_valid),
    .rf_valid   (rf_valid),
    .busy_status(mem_busy_status),
    .cmdwdata   (cmdwdata),
    .txwdata    (txwdata),
    .mem_prdata (mem_prdata),
    .cmdwe      (cmdwe),
    .txwe       (txwe),
    .rxre       (rxre)
);

// ------------------------------------------------------------------
// MMIO
// ------------------------------------------------------------------
sdram_master_mmio u_mmio (
    .clk            (clk2),
    .rstb           (rstb),
    .init_done_req  (init_done_req),
    .paddr          (paddr),
    .pwdata         (pwdata),
    .tm_valid       (tm_valid),
    .rf_valid       (rf_valid),
    .busy           (mem_busy_status),
    .rxempty        (rxempty),
    .txfull         (txfull),
    .mrs_valid      (mrs_valid),
    .mrs_req_ack    (mrs_req_ack),
    .timing_req_ack (timing_req_ack),
    .refresh_req_ack(refresh_req_ack),
    .prdata         (cfg_prdata),
    .init_done_ack  (init_done_ack),
    .mrs_val_reg    (mrs_val_reg),
    .timing_reg     (timing_reg),
    .refresh_reg    (refresh_reg),
    .mrs_req        (mrs_req),
    .timing_req     (timing_req),
    .refresh_req    (refresh_req)
);

//sdram mem or register mem
assign sdram_prdata_sel = (paddr >= 32'h6000_0000) && (paddr <= (32'h6000_0000 + 32'h0200_0000 - 1'b1));
assign prdata = sdram_prdata_sel ? mem_prdata : cfg_prdata;

endmodule
