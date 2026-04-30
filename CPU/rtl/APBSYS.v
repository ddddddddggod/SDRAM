`timescale 1ns / 1ps
module APBSYS 
(
    input  wire        HCLK,
    input  wire        PCLK,
    input  wire        CLK1,
    input  wire        HRESETn,
    input  wire [31:0] HADDR,
    input  wire [1:0]  HTRANS,
    input  wire        HWRITE,
    input  wire [2:0]  HSIZE,
    input  wire [31:0] HWDATA,
    input  wire        HSEL,
    input  wire        HREADY,
    output wire [31:0] HRDATA,
    output wire        HREADYOUT,

    output wire        cke,
    output wire        cs,
    output wire        ras,
    output wire        cas,
    output wire        we,
    output wire [1:0]  bs,
    output wire [12:0] addr,
    output wire [1:0]  dqm,
    inout  wire [15:0] dq
);

wire [31:0] PADDR;
wire        PWRITE;
wire [31:0] PWDATA;
wire        PENABLE;
wire        PSEL_DUMMY1;

// CDC
wire        pready_req;
wire        pready_ack;
wire        pready_signal;
wire        pena_req;
wire        pwrite_req;
wire        psel_req;
wire [31:0] prdata_cdc;

// slave cdc 
wire        pena_cdc;
wire        pwrite_cdc;
wire        psel_cdc;
wire [31:0] pwdata_cdc;
wire [31:0] paddr_cdc;


wire [31:0] prdata;
wire        pready;

AHB2APB uAHB2APB (
    .HCLK     (HCLK),
    .HRESETn  (HRESETn),
    .HADDR    (HADDR),
    .HSEL     (HSEL),
    .HREADY   (HREADY),
    .HTRANS   (HTRANS),
    .HSIZE    (HSIZE),
    .HWDATA   (HWDATA),
    .HWRITE   (HWRITE),
    .HRDATA   (HRDATA),
    .HREADYOUT(HREADYOUT),
    .PCLK     (),
    .PRESETn  (),
    .PADDR    (PADDR),
    .PWRITE   (PWRITE),
    .PWDATA   (PWDATA),
    .PENABLE  (PENABLE),
    .PREADY   (pready_signal),  
    .PRDATA   (prdata_cdc)      
);

// assign PSEL_DUMMY1 = ((PADDR[23:20] == 4'h0) && (~HREADYOUT | PENABLE));
wire PSEL_DATA = ((PADDR[31:28] == 4'h6) && (~HREADYOUT | PENABLE));
wire PSEL_CTRL = ((PADDR[31:28] == 4'h5) && (~HREADYOUT | PENABLE));
assign PSEL_DUMMY1 = PSEL_DATA || PSEL_CTRL;


apb_rx_cdc u_apb_cdc (
    .clk            (HCLK),
    .rstb           (HRESETn),
    .pready_req     (pready_req),
    .pena           (PENABLE),
    .pwrite         (PWRITE),
    .psel           (PSEL_DUMMY1),
    .prdata         (prdata),
    .pready_ack     (pready_ack),
    .pready_signal  (pready_signal),
    .pena_req       (pena_req),
    .pwrite_req     (pwrite_req),
    .psel_req       (psel_req),
    .prdata_cdc     (prdata_cdc)
);

sdram_slave_cdc u_sdram_cdc (
    .clk            (PCLK),
    .rstb           (HRESETn),
    .pready         (pready),
    .pready_ack     (pready_ack),
    .pena_req       (pena_req),
    .pwrite_req     (pwrite_req),
    .psel_req       (psel_req),
    .pwdata         (PWDATA),
    .paddr          (PADDR),
    .pready_req     (pready_req),
    .pena_cdc       (pena_cdc),
    .pwrite_cdc     (pwrite_cdc),
    .psel_cdc       (psel_cdc),
    .pwdata_cdc     (pwdata_cdc),
    .paddr_cdc      (paddr_cdc)
);

sdram_master_top u_dut (
    .clk1   (CLK1),
    .clk2   (PCLK),
    .rstb   (HRESETn),
    .pwrite (pwrite_cdc),
    .paddr  (paddr_cdc),
    .pena   (pena_cdc),
    .psel   (psel_cdc),
    .pwdata (pwdata_cdc),

    .pready (pready),
    .prdata (prdata),

    .cke    (cke),
    .cs     (cs),
    .ras    (ras),
    .cas    (cas),
    .we     (we),
    .bs     (bs),
    .addr   (addr),
    .dqm    (dqm),
    .dq     (dq)
);


endmodule
