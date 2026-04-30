`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//END USER LICENCE AGREEMENT                                                    //
//                                                                              //
//Copyright (c) 2012, ARM All rights reserved.                                  //
//                                                                              //
//THIS END USER LICENCE AGREEMENT (LICENCE) IS A LEGAL AGREEMENT BETWEEN      //
//YOU AND ARM LIMITED ("ARM") FOR THE USE OF THE SOFTWARE EXAMPLE ACCOMPANYING  //
//THIS LICENCE. ARM IS ONLY WILLING TO LICENSE THE SOFTWARE EXAMPLE TO YOU ON   //
//CONDITION THAT YOU ACCEPT ALL OF THE TERMS IN THIS LICENCE. BY INSTALLING OR  //
//OTHERWISE USING OR COPYING THE SOFTWARE EXAMPLE YOU INDICATE THAT YOU AGREE   //
//TO BE BOUND BY ALL OF THE TERMS OF THIS LICENCE. IF YOU DO NOT AGREE TO THE   //
//TERMS OF THIS LICENCE, ARM IS UNWILLING TO LICENSE THE SOFTWARE EXAMPLE TO    //
//YOU AND YOU MAY NOT INSTALL, USE OR COPY THE SOFTWARE EXAMPLE.                //
//                                                                              //
//ARM hereby grants to you, subject to the terms and conditions of this Licence,//
//a non-exclusive, worldwide, non-transferable, copyright licence only to       //
//redistribute and use in source and binary forms, with or without modification,//
//for academic purposes provided the following conditions are met:              //
//a) Redistributions of source code must retain the above copyright notice, this//
//list of conditions and the following disclaimer.                              //
//b) Redistributions in binary form must reproduce the above copyright notice,  //
//this list of conditions and the following disclaimer in the documentation     //
//and/or other materials provided with the distribution.                        //
//                                                                              //
//THIS SOFTWARE EXAMPLE IS PROVIDED BY THE COPYRIGHT HOLDER "AS IS" AND ARM     //
//EXPRESSLY DISCLAIMS ANY AND ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING     //
//WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR //
//PURPOSE, WITH RESPECT TO THIS SOFTWARE EXAMPLE. IN NO EVENT SHALL ARM BE LIABLE/
//FOR ANY DIRECT, INDIRECT, INCIDENTAL, PUNITIVE, OR CONSEQUENTIAL DAMAGES OF ANY/
//KIND WHATSOEVER WITH RESPECT TO THE SOFTWARE EXAMPLE. ARM SHALL NOT BE LIABLE //
//FOR ANY CLAIMS, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, //
//TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE    //
//EXAMPLE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE EXAMPLE. FOR THE AVOIDANCE/
// OF DOUBT, NO PATENT LICENSES ARE BEING LICENSED UNDER THIS LICENSE AGREEMENT.//
//////////////////////////////////////////////////////////////////////////////////


module AHB2APB(
// Global signals --------------------------------------------------------------
  input wire          HCLK,
  input wire          HRESETn,
  
// AHB Slave inputs ------------------------------------------------------------  
  input wire  [31:0]  HADDR,
  input wire  [1:0]   HTRANS,
  input wire          HWRITE,
  input wire  [2:0]   HSIZE,
  input wire  [31:0]  HWDATA,
  input wire          HSEL,
  input wire          HREADY,
  
// APB Master inputs -----------------------------------------------------------
  input wire  [31:0]  PRDATA,
  input wire          PREADY,
  
// AHB Slave outputs -----------------------------------------------------------
  output wire [31:0]  HRDATA,
  output reg          HREADYOUT,
  
// APB Master outputs ----------------------------------------------------------
  output wire [31:0]  PWDATA,
  output reg          PENABLE,
  output reg  [31:0]  PADDR,
  output reg          PWRITE,
  
  output wire         PCLK,
  output wire         PRESETn
);
  
//Constants

  `define ST_IDLE 2'b00
  `define ST_SETUP 2'b01
  `define ST_ACCESS 2'b11


  wire          Transfer;
  wire          ACRegEn;
  reg   [31:0]  last_HADDR;
  reg           last_HWRITE;
  reg   [2:0]   last_HSIZE;
  
  wire  [31:0]  HADDR_Mux;
  
  reg   [1:0]   CurrentState;
  reg   [1:0]   NextState;
  
  reg           HREADY_next;  
  wire          PWRITE_next;
  wire          PENABLE_next;
  wire          APBEn;
  
  
  // assign PCLK = HCLK;
  assign PRESETn = HRESETn;
  
  assign Transfer = HSEL & HREADY & HTRANS[1];
  
  assign ACRegEn = HSEL & HREADY;
  
  //Set register values of AHB signals
  
  always @ (posedge HCLK, negedge HRESETn)
  begin
    if(!HRESETn)
      begin
        last_HADDR <= {32{1'b0}};
        last_HWRITE <= 1'b0;
        last_HSIZE <= 3'b010;
      end
    
    else
      begin
        if(ACRegEn)
          begin
            last_HADDR <= HADDR;
            last_HWRITE <= HWRITE;
            last_HSIZE <= HSIZE;
          end
      end
  end
  
  
// Next State Logic

  always @ (CurrentState,PREADY, Transfer)
  begin
    case (CurrentState)
      `ST_IDLE: 
        begin
          if(Transfer)
            NextState = `ST_SETUP;
          else
            NextState = `ST_IDLE;
        end
      
      `ST_SETUP:
        begin
          NextState = `ST_ACCESS;
        end
      
      `ST_ACCESS:
        begin
          if(!PREADY)
            NextState = `ST_ACCESS;
          else
            begin
              if(Transfer)
                NextState = `ST_SETUP;
              else
                NextState = `ST_IDLE;
            end
        end
      default:
        NextState = `ST_IDLE;
    endcase
  end
  
// State Machine

  always @ (posedge HCLK, negedge HRESETn)
  begin
    if(!HRESETn)
      CurrentState <= `ST_IDLE;
    else
      CurrentState <= NextState;
  end
  
  
//HREADYOUT

  always @ (NextState, PREADY)
  begin
    case (NextState)
      `ST_IDLE:
        HREADY_next = 1'b1;
      `ST_SETUP:
        HREADY_next = 1'b0;
      `ST_ACCESS: 
        HREADY_next = PREADY;
      default:
        HREADY_next = 1'b1;
    endcase
  end

  always @(posedge HCLK, negedge HRESETn)
  begin
    if(!HRESETn)
      HREADYOUT <= 1'b1;
    else
      HREADYOUT <= HREADY_next;
  end

  
// HADDRMux
  assign HADDR_Mux = ((NextState == `ST_SETUP) ? HADDR : last_HADDR);

//APBen
  assign APBEn = ((NextState == `ST_SETUP) ? 1'b1 : 1'b0);

//PADDR
  always @ (posedge HCLK, negedge HRESETn)
  begin
    if (!HRESETn)
      PADDR <= {32{1'b0}};
    else
      begin
        if (APBEn)
          PADDR <= HADDR_Mux;
      end
  end

//PWDATA
wire tx_byte = ~last_HSIZE[1] & ~last_HSIZE[0];
wire tx_half = ~last_HSIZE[1] &  last_HSIZE[0];
wire tx_word =  last_HSIZE[1];

wire [31:0] PWDATA_align =
    tx_word                    ? HWDATA :
    (tx_half && last_HADDR[1]) ? {16'h0000, HWDATA[31:16]} :
    tx_half                    ? {16'h0000, HWDATA[15:0]} :
    (tx_byte && (last_HADDR[1:0] == 2'b11)) ? {24'h0, HWDATA[31:24]} :
    (tx_byte && (last_HADDR[1:0] == 2'b10)) ? {24'h0, HWDATA[23:16]} :
    (tx_byte && (last_HADDR[1:0] == 2'b01)) ? {24'h0, HWDATA[15:8]}  :
                                              {24'h0, HWDATA[7:0]};

assign PWDATA = PWDATA_align;


//PENABLE

  assign PENABLE_next = ((NextState == `ST_ACCESS) ? 1'b1 : 1'b0);
  
  always @ (posedge HCLK, negedge HRESETn)
  begin
    if(!HRESETn)
      PENABLE <= 1'b0;
    else
      PENABLE <= PENABLE_next;
  end
  
//PWRITE

  assign PWRITE_next = ((NextState == `ST_SETUP) ? HWRITE : last_HWRITE);

  always @ (posedge HCLK, negedge HRESETn)
  begin
    if(!HRESETn)
      PWRITE <= 1'b0;
    else
      begin
        if (APBEn)
          PWRITE <= PWRITE_next;
      end
  end


//HRDATA
wire [31:0] HRDATA_align =
    tx_word                    ? PRDATA :
    (tx_half && last_HADDR[1]) ? {PRDATA[15:0], 16'h0000} :
    tx_half                    ? {16'h0000, PRDATA[15:0]} :
    (tx_byte && (last_HADDR[1:0] == 2'b11)) ? {PRDATA[7:0], 24'h0} :
    (tx_byte && (last_HADDR[1:0] == 2'b10)) ? {8'h0, PRDATA[7:0], 16'h0} :
    (tx_byte && (last_HADDR[1:0] == 2'b01)) ? {16'h0, PRDATA[7:0], 8'h0} :
                                              {24'h0, PRDATA[7:0]};

assign HRDATA = HRDATA_align;


`ifdef CPU_DEBUG_APB
always @(posedge HCLK) begin
  if (APBEn) begin
    $display("[%0t] AHB2APB SETUP HADDR=0x%08h HWRITE=%0b HWDATA=0x%08h HSIZE=%0d PWRITE_next=%0b",
             $time, HADDR_Mux, ((NextState == `ST_SETUP) ? HWRITE : last_HWRITE), HWDATA, last_HSIZE, PWRITE_next);
  end
end
`endif


endmodule
