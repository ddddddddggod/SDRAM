`timescale 1ns / 1ps
module AHBLITE_SYS 
(
    input  wire        SYS_CLK,
    input  wire        PCLK,
    input  wire        CLK1,
    input  wire        RESETn,

    output cke,
    output cs,
    output ras,
    output cas,
    output we,
    output [1:0] bs,
    output [12:0] addr,
    output [1:0] dqm,
    inout [15:0] dq     
);


wire        HCLK;
wire        HRESETn;
wire [31:0] HADDR, HWDATA, HRDATA;
wire HWRITE, HMASTLOCK, HRESP, HREADY;
wire [1:0]  HTRANS;
wire [2:0]  HBURST, HSIZE;
wire [3:0]  HPROT, MUX_SEL;
wire HSEL_MEM, HSEL_APB, HSEL_NOMAP;
wire [31:0] HRDATA_MEM, HRDATA_APB;
wire HREADYOUT_MEM, HREADYOUT_APB;
wire LOCKUP;
wire [15:0] IRQ;
wire interrupt;               

assign HRESP   = 1'b0;
assign IRQ = {15'b0, interrupt};  

//CLOCK DIVIDER & RESET
ClockDiv    uClockDiv   (
    .CLK_I(SYS_CLK),
    .CLK_O(HCLK)
    );
assign HRESETn = RESETn;


// Cortex-M0
CORTEXM0DS u_cortexm0ds (
    .HCLK        (HCLK),
    .HRESETn     (HRESETn),
    .HADDR       (HADDR),
    .HBURST      (HBURST),
    .HMASTLOCK   (HMASTLOCK),
    .HPROT       (HPROT),
    .HSIZE       (HSIZE),
    .HTRANS      (HTRANS),
    .HWDATA      (HWDATA),
    .HWRITE      (HWRITE),
    .HRDATA      (HRDATA),
    .HREADY      (HREADY),
    .HRESP       (HRESP),
    .NMI         (1'b0),
    .IRQ         (IRQ),
    .TXEV        (),
    .RXEV        (1'b0),
    .LOCKUP      (LOCKUP),
    .SYSRESETREQ (),
    .SLEEPING    ()
);

// Address Decoder
AHBDCD uAHBDCD (
    .HADDR      (HADDR),
    .HSEL_S0    (HSEL_MEM),
    .HSEL_S1    (HSEL_APB),
    .HSEL_S2    (),
    .HSEL_S3    (),
    .HSEL_S4    (),
    .HSEL_S5    (),
    .HSEL_S6    (),
    .HSEL_S7    (),
    .HSEL_S8    (),
    .HSEL_S9    (),
    .HSEL_NOMAP (HSEL_NOMAP),
    .MUX_SEL    (MUX_SEL)
);

// Slave MUX
AHBMUX uAHBMUX (
    .HCLK           (HCLK),
    .HRESETn        (HRESETn),
    .MUX_SEL        (MUX_SEL),
    .HRDATA_S0      (HRDATA_MEM),
    .HRDATA_S1      (HRDATA_APB),
    .HRDATA_S2      (),
    .HRDATA_S3      (),
    .HRDATA_S4      (),
    .HRDATA_S5      (),
    .HRDATA_S6      (),
    .HRDATA_S7      (),
    .HRDATA_S8      (),
    .HRDATA_S9      (),
    .HRDATA_NOMAP   (32'hDEADBEEF),
    .HREADYOUT_S0   (HREADYOUT_MEM),
    .HREADYOUT_S1   (HREADYOUT_APB),
    .HREADYOUT_S2   (1'b1),
    .HREADYOUT_S3   (1'b1),
    .HREADYOUT_S4   (1'b1),
    .HREADYOUT_S5   (1'b1),
    .HREADYOUT_S6   (1'b1),
    .HREADYOUT_S7   (1'b1),
    .HREADYOUT_S8   (1'b1),
    .HREADYOUT_S9   (1'b1),
    .HREADYOUT_NOMAP(1'b1),
    .HRDATA         (HRDATA),
    .HREADY         (HREADY)
);

// Memory
AHB2MEM uAHB2MEM (
    .HSEL      (HSEL_MEM),
    .HCLK      (HCLK),
    .HRESETn   (HRESETn),
    .HREADY    (HREADY),
    .HADDR     (HADDR),
    .HTRANS    (HTRANS),
    .HWRITE    (HWRITE),
    .HSIZE     (HSIZE),
    .HWDATA    (HWDATA),
    .HRDATA    (HRDATA_MEM),
    .HREADYOUT (HREADYOUT_MEM),
    .LED       ()
);

// APB System
APBSYS uAPBSYS (
    .HCLK      (HCLK),
    .PCLK      (PCLK),
    .CLK1      (CLK1),
    .HRESETn   (HRESETn),
    .HADDR     (HADDR),
    .HTRANS    (HTRANS),
    .HWRITE    (HWRITE),
    .HWDATA    (HWDATA),
    .HSIZE     (HSIZE),
    .HSEL      (HSEL_APB),
    .HREADY    (HREADY),
    .HRDATA    (HRDATA_APB),
    .HREADYOUT (HREADYOUT_APB),

    .cke        (cke),
    .cs         (cs),
    .ras        (ras),
    .cas        (cas),
    .we         (we),
    .bs         (bs),
    .addr       (addr),
    .dqm        (dqm),
    .dq         (dq)
);

endmodule
