`timescale 1ns / 1ps
module sdram_master_apb_slave (
    input               clk,
    input               rstb,
    input               pwrite,
    input      [31:0]   paddr,
    input      [31:0]   pwdata,
    input               pena,
    input               psel,
    input               cmdfull,
    input               txfull,
    input      [3:0]    tx_diff,
    input      [3:0]    rx_diff,
    input               rxempty,
    input      [15:0]   rxrdata,

    output              pready,
    output              mrs_valid,
    output              tm_valid,
    output              rf_valid,
    output              busy_status,
    output     [28:0]   cmdwdata,
    output     [15:0]   txwdata,
    output     [31:0]   mem_prdata,
    output              cmdwe,
    output              txwe,
    output              rxre
);

localparam [1:0] apb_idle   = 2'd0;
localparam [1:0] apb_setup  = 2'd1;
localparam [1:0] apb_access = 2'd2;

reg [1:0] apb_state, apb_state_n;

always @(posedge clk or negedge rstb) begin
    if (!rstb)
        apb_state <= apb_idle;
    else
        apb_state <= apb_state_n;
end

always @(*) begin
    apb_state_n = apb_state;
    case (apb_state)
        apb_idle:   apb_state_n = (psel) ? apb_setup : apb_idle;
        apb_setup:  apb_state_n = (pena) ? apb_access : apb_setup;
        apb_access: apb_state_n = (pready) ? apb_idle : apb_access;
    endcase
end

wire access   = (apb_state == apb_access);

//___________Output logic________________________________________--
localparam [31:0] mrs_val_addr = 32'h5000_0000;
localparam [31:0] timing_addr  = 32'h5000_0004;
localparam [31:0] refresh_addr = 32'h5000_0008;
localparam [31:0] status_addr  = 32'h5000_0010;

localparam [31:0] sdram_base_addr = 32'h6000_0000;
localparam [31:0] sdram_size      = 32'h0200_0000;
localparam [31:0] sdram_end_addr  = sdram_base_addr + sdram_size - 1'b1;

wire mem_pready;
wire mem_busy;
wire register_write_sel;
wire register_read_sel;

assign register_sel = (paddr == mrs_val_addr) || (paddr == timing_addr) || (paddr == refresh_addr) || (paddr == status_addr) ;

assign mem_sel = (paddr >= sdram_base_addr) && (paddr <= sdram_end_addr); //sdram address
assign invalid_sel = !register_sel && !mem_sel;//invalid address

assign mrs_write = access && pwrite && (paddr == mrs_val_addr);
assign register_write_sel = access && pwrite && register_sel;
assign register_read_sel  = access && !pwrite && register_sel;
assign register_pready = (access && invalid_sel) ||
                         register_read_sel ||
                         (register_write_sel && !mem_busy);

assign mem_wr_req = access && mem_sel && pwrite; //write request
assign mem_rd_req = access && mem_sel && !pwrite; //read request


//caculate bl length 
reg [3:0] burst_len_decode;
always @(*) begin
    case (pwdata[2:0])
        3'b000: burst_len_decode = 4'd1;
        3'b001: burst_len_decode = 4'd2;
        3'b010: burst_len_decode = 4'd4;
        3'b011: burst_len_decode = 4'd8;
        default: burst_len_decode = 4'd1;
    endcase
end
reg [3:0] burst_len_cfg;
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        burst_len_cfg <= 4'd1;
    end else if (mrs_write) begin
        burst_len_cfg <= burst_len_decode;
    end
end

sdram_master_mem_access u_mem_access (
    .clk            (clk),
    .rstb           (rstb),
    .mem_wr_req     (mem_wr_req),
    .mem_rd_req     (mem_rd_req),
    .paddr          (paddr),
    .pwdata         (pwdata),
    .burst_len_cfg  (burst_len_cfg),
    .cmdfull        (cmdfull),
    .tx_diff        (tx_diff),
    .rx_diff        (rx_diff),
    .txfull         (txfull),
    .rxempty        (rxempty),
    .rxrdata        (rxrdata),
    .pready         (mem_pready),
    .busy           (mem_busy),
    .cmdwdata       (cmdwdata),
    .txwdata        (txwdata),
    .cmdwe          (cmdwe),
    .txwe           (txwe),
    .rxre           (rxre),
    .prdata         (mem_prdata)
);
assign pready    = register_pready || mem_pready; //wrong address or mem ready
assign mrs_valid = access && pwrite && (paddr == mrs_val_addr) && !mem_busy;
assign tm_valid  = access && pwrite && (paddr == timing_addr)  && !mem_busy;
assign rf_valid  = access && pwrite && (paddr == refresh_addr) && !mem_busy;
assign busy_status = mem_busy;



endmodule
