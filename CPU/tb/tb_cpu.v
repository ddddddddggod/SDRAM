`timescale 1ns / 1ps

module tb_cpu;

`ifndef TEST_CLK1_FREQ_MHZ
`define TEST_CLK1_FREQ_MHZ 166
`endif

localparam integer CLK1_FREQ_MHZ    = `TEST_CLK1_FREQ_MHZ;
localparam integer SYS_CLK_FREQ_MHZ = 100;
localparam integer PCLK_FREQ_MHZ    = 50;

localparam [31:0] FW_STATUS_PASS = 32'h600D0001;
localparam [31:0] FW_STATUS_FAIL = 32'hDEAD0000;

localparam integer FW_STATUS_IDX = 32'h0000_0F00 >> 2;
localparam integer FW_ERROR_IDX  = 32'h0000_0F04 >> 2;
localparam integer FW_RDBACK0_IDX= 32'h0000_0F08 >> 2;

reg CLK1;
reg SYS_CLK;
reg PCLK;
reg reset_n;
integer cycles;

wire        cke;
wire        cs;
wire        ras;
wire        cas;
wire        we_sdram;
wire [1:0]  bs;
wire [12:0] sdram_addr;
wire [1:0]  dqm;
wire [15:0] dq;

/* Added report/check mailbox */
localparam integer FW_TEST_ID_IDX    = 32'h0000_0F08 >> 2;
localparam integer FW_TEST_STATE_IDX = 32'h0000_0F0C >> 2;
localparam integer FW_TEST_EVENT_IDX = 32'h0000_0F10 >> 2;

localparam [31:0] FW_TEST_STATE_IDLE  = 32'd0;
localparam [31:0] FW_TEST_STATE_START = 32'd1;
localparam [31:0] FW_TEST_STATE_DONE  = 32'd2;

`ifdef BL1
localparam integer TEST_BL = 1;
`elsif BL2
localparam integer TEST_BL = 2;
`elsif BL8
localparam integer TEST_BL = 8;
`else
localparam integer TEST_BL = 4;
`endif

`ifdef T6CL2
localparam integer TEST_CL = 2;
`else
localparam integer TEST_CL = 3;
`endif

localparam integer TEST_WORD_COUNT =
    (TEST_BL == 8) ? 4 :
    (TEST_BL == 4) ? 2 : 1;
localparam integer BOUNDARY_START_COL = 512 - (TEST_WORD_COUNT * 2);
localparam integer FULL_ROW_WORD_COUNT = 256;
localparam integer TEST9_SPAN_WORD_COUNT = 16;
localparam integer TEST_REFRESH_PERIOD = ((64 * CLK1_FREQ_MHZ * 1000) + 8191) / 8192;
localparam integer TEST2_REFRESH_CFG = 64;

reg [31:0] last_test_id;
reg [31:0] last_test_state;
reg [31:0] curr_test_id;
reg [31:0] curr_test_state;
reg [31:0] last_test_event;
reg [31:0] curr_test_event;
integer report_fd;
integer report_fail_count;
integer test1_error_count;
integer test2_error_count;
integer test3_error_count;
integer test4_error_count;
integer test5_error_count;
integer test6_error_count;
integer test8_error_count;
integer test9_error_count;
reg test8_skipped;
reg [1023:0] report_path;
reg verbose_compare_console;
reg test2_track_active;
time test2_refresh_start_time;
time test2_refresh_window_time;
time test2_cmd_during_trc_time;
time test2_actual_write_time;
reg  test2_cmd_during_trc;
reg [1:0] test2_mem_wr_req_sync;

//================================================================
// Clock & Reset
//================================================================
localparam CLK1_FREQ =166;  // MHz
localparam SYS_CLK_FREQ = 100; // MHz
localparam PCLK_FREQ = 100; // MHz

initial CLK1 = 1'b0;
always #(1000.0/(2.0*CLK1_FREQ)) CLK1 = ~CLK1;

initial SYS_CLK = 1'b0;
always #(1000.0/(2.0*SYS_CLK_FREQ)) SYS_CLK = ~SYS_CLK;

initial PCLK = 1'b0;
always #(1000.0/(2.0*PCLK_FREQ)) PCLK = ~PCLK;

initial begin
    reset_n = 1'b0;
    repeat (20) @(posedge SYS_CLK);
    reset_n = 1'b1;
end
//================================================================
// DUT
//================================================================
AHBLITE_SYS u_dut (
    .SYS_CLK (SYS_CLK),
    .PCLK    (PCLK),
    .CLK1    (CLK1),
    .RESETn  (reset_n),
    .cke     (cke),
    .cs      (cs),
    .ras     (ras),
    .cas     (cas),
    .we      (we_sdram),
    .bs      (bs),
    .addr    (sdram_addr),
    .dqm     (dqm),
    .dq      (dq)
);

W9825G6KH u_ram (
    .Dq    (dq),
    .Addr  (sdram_addr),
    .Bs    (bs),
    .Clk   (CLK1),
    .Cke   (cke),
    .Cs_n  (cs),
    .Ras_n (ras),
    .Cas_n (cas),
    .We_n  (we_sdram),
    .Dqm   (dqm)
);

//================================================================
// Wave dump
//================================================================
`ifndef VCS
initial begin
    $shm_open("wave");
    $shm_probe("ASM", tb_cpu);
end
`else
initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb_cpu);
end
`endif
//================================================================
// for Display
//================================================================
task automatic dump_readbacks;
    begin
        $display("[%0t] FW STATUS = 0x%08h", $time, u_dut.uAHB2MEM.memory[FW_STATUS_IDX]);
        $display("[%0t] FW ERROR  = 0x%08h", $time, u_dut.uAHB2MEM.memory[FW_ERROR_IDX]);
        $display("[%0t] FW TEST ID    = %0d", $time, u_dut.uAHB2MEM.memory[FW_TEST_ID_IDX]);
        $display("[%0t] FW TEST STATE = %0d", $time, u_dut.uAHB2MEM.memory[FW_TEST_STATE_IDX]);
        $display("[%0t] FW TEST EVENT = 0x%08h", $time, u_dut.uAHB2MEM.memory[FW_TEST_EVENT_IDX]);
    end
endtask

function integer bank_mem_index;
    input integer row;
    input integer col;
    begin
        bank_mem_index = (row << 9) + col;
    end
endfunction

function [15:0] bank_mem_value;
    input integer bank;
    input integer row;
    input integer col;
    begin
        case (bank)
            0: bank_mem_value = u_ram.Bank0[bank_mem_index(row, col)];
            1: bank_mem_value = u_ram.Bank1[bank_mem_index(row, col)];
            2: bank_mem_value = u_ram.Bank2[bank_mem_index(row, col)];
            default: bank_mem_value = u_ram.Bank3[bank_mem_index(row, col)];
        endcase
    end
endfunction

function [15:0] pattern_halfword;
    input integer beat;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    begin
        case (beat)
            0: pattern_halfword = word0[15:0];
            1: pattern_halfword = word0[31:16];
            2: pattern_halfword = word1[15:0];
            3: pattern_halfword = word1[31:16];
            4: pattern_halfword = word2[15:0];
            5: pattern_halfword = word2[31:16];
            6: pattern_halfword = word3[15:0];
            default: pattern_halfword = word3[31:16];
        endcase
    end
endfunction

task automatic log_expect_halfword;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer col;
    input [15:0] expected;
    input integer count_fail;
    reg [15:0] actual;
    begin
        actual = bank_mem_value(bank, row, col);
        if (actual === expected) begin
            if (report_fd != 0)
                $fdisplay(report_fd, "%0s | B%0d R%0d C%0d | EXP=0x%04h ACT=0x%04h | PASS",
                          test_name, bank, row, col, expected, actual);
            if (verbose_compare_console)
                $display("[%0t] %0s | B%0d R%0d C%0d | EXP=0x%04h ACT=0x%04h | PASS",
                         $time, test_name, bank, row, col, expected, actual);
        end else begin
            if (report_fd != 0)
                $fdisplay(report_fd, "%0s | B%0d R%0d C%0d | EXP=0x%04h ACT=0x%04h | FAIL",
                          test_name, bank, row, col, expected, actual);
            if (verbose_compare_console)
                $display("[%0t] %0s | B%0d R%0d C%0d | EXP=0x%04h ACT=0x%04h | FAIL",
                         $time, test_name, bank, row, col, expected, actual);
            if (count_fail != 0)
                report_fail_count = report_fail_count + 1;
        end
    end
endtask

task automatic log_compare_halfword;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer col;
    input [15:0] expected;
    begin
        log_expect_halfword(test_name, bank, row, col, expected, 1);
    end
endtask

task automatic log_compare_masked_halfword;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer col;
    reg [15:0] actual;
    begin
        actual = bank_mem_value(bank, row, col);
        if (actual === 16'hxxxx) begin
            if (report_fd != 0)
                $fdisplay(report_fd, "%0s | B%0d R%0d C%0d | EXP=MASKED(xxxx) ACT=0x%04h | PASS",
                          test_name, bank, row, col, actual);
            if (verbose_compare_console)
                $display("[%0t] %0s | B%0d R%0d C%0d | EXP=MASKED(xxxx) ACT=0x%04h | PASS",
                         $time, test_name, bank, row, col, actual);
        end else begin
            if (report_fd != 0)
                $fdisplay(report_fd, "%0s | B%0d R%0d C%0d | EXP=MASKED(xxxx) ACT=0x%04h | FAIL",
                          test_name, bank, row, col, actual);
            if (verbose_compare_console)
                $display("[%0t] %0s | B%0d R%0d C%0d | EXP=MASKED(xxxx) ACT=0x%04h | FAIL",
                         $time, test_name, bank, row, col, actual);
            report_fail_count = report_fail_count + 1;
        end
    end
endtask

task automatic log_compare_words;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer start_col;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    integer beat;
    reg [15:0] expected;
    begin
        for (beat = 0; beat < (TEST_WORD_COUNT * 2); beat = beat + 1) begin
            expected = pattern_halfword(beat, word0, word1, word2, word3);
            log_compare_halfword(test_name, bank, row, start_col + beat, expected);
        end
    end
endtask

task automatic log_compare_single_word;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer start_col;
    input [31:0] word_value;
    begin
        log_compare_halfword(test_name, bank, row, start_col + 0, word_value[15:0]);
        log_compare_halfword(test_name, bank, row, start_col + 1, word_value[31:16]);
    end
endtask

task automatic log_compare_auto_words;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer start_col;
    input integer word_count;
    input [31:0] base_value;
    integer i;
    reg [31:0] word_value;
    begin
        for (i = 0; i < word_count; i = i + 1) begin
            word_value = base_value + i;
            log_compare_halfword(test_name, bank, row, start_col + (i * 2) + 0, word_value[15:0]);
            log_compare_halfword(test_name, bank, row, start_col + (i * 2) + 1, word_value[31:16]);
        end
    end
endtask

task automatic log_compare_auto_words_summary;
    input [8*64-1:0] test_name;
    input integer bank;
    input integer row;
    input integer start_col;
    input integer word_count;
    input [31:0] base_value;
    integer i;
    integer local_fail_count;
    reg [31:0] word_value;
    reg [15:0] expected_lo;
    reg [15:0] expected_hi;
    reg [15:0] actual_lo;
    reg [15:0] actual_hi;
    begin
        local_fail_count = 0;
        for (i = 0; i < word_count; i = i + 1) begin
            word_value = base_value + i;
            expected_lo = word_value[15:0];
            expected_hi = word_value[31:16];
            actual_lo = bank_mem_value(bank, row, start_col + (i * 2) + 0);
            actual_hi = bank_mem_value(bank, row, start_col + (i * 2) + 1);

            if (actual_lo !== expected_lo)
                local_fail_count = local_fail_count + 1;
            if (actual_hi !== expected_hi)
                local_fail_count = local_fail_count + 1;
        end

        report_fail_count = report_fail_count + local_fail_count;

        if (report_fd != 0)
            $fdisplay(report_fd, "%0s | WORDS=%0d | RANGE=B%0d R%0d C%0d..C%0d | RESULT=%0s",
                      test_name, word_count, bank, row, start_col,
                      start_col + (word_count * 2) - 1,
                      (local_fail_count == 0) ? "PASS" : "FAIL");

        $display("[%0t] %0s | CLK1=%0d BL=%0d CL=%0d | RESULT=%0s",
                 $time, test_name, CLK1_FREQ_MHZ, TEST_BL, TEST_CL,
                 (local_fail_count == 0) ? "PASS" : "FAIL");
    end
endtask

  
task automatic log_test2_refresh_summary;
    begin
        $display("[%0t] TEST2_TRC_CFG               = %0d cycles", $time, u_dut.uAPBSYS.u_dut.u_ctrl.tRC);
        $display("[%0t] TEST2_REFRESH_START_TIME    = %0t", $time, test2_refresh_start_time);
        $display("[%0t] TEST2_WRITE_REQ_DURING_TRC  = %0t", $time, test2_cmd_during_trc_time);
        $display("[%0t] TEST2_ACTUAL_WRITE_CMD_TIME = %0t", $time, test2_actual_write_time);
        $display("[%0t] TEST2_REQ_DURING_TRC        = %0s", $time, test2_cmd_during_trc ? "YES" : "NO");

        if (report_fd != 0) begin
            $fdisplay(report_fd, "TEST2_TRC_CFG               = %0d cycles", u_dut.uAPBSYS.u_dut.u_ctrl.tRC);
            $fdisplay(report_fd, "TEST2_REFRESH_START_TIME    = %0t", test2_refresh_start_time);
            $fdisplay(report_fd, "TEST2_WRITE_REQ_DURING_TRC  = %0t", test2_cmd_during_trc_time);
            $fdisplay(report_fd, "TEST2_ACTUAL_WRITE_CMD_TIME = %0t", test2_actual_write_time);
            $fdisplay(report_fd, "TEST2_REQ_DURING_TRC        = %0s", test2_cmd_during_trc ? "YES" : "NO");
        end
    end
endtask

task automatic print_final_error_summary;
    begin
        $display("============================================================");
        $display("FINAL TEST ERROR SUMMARY");
        $display("CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
        $display("DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
        $display("TEST2_REFRESH_CFG       = %0d cycles (0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
        $display("TEST 1 NORMAL_CONTIGUOUS_WRITE_READ | ERROR COUNT = %0d", test1_error_count);
        $display("TEST 2 WRITE_REQUEST_DURING_REFRESH_TRC | ERROR COUNT = %0d", test2_error_count);
        $display("TEST 3 NON_CONTIGUOUS_THEN_CONTIGUOUS | ERROR COUNT = %0d", test3_error_count);
        $display("TOTAL COMPARE FAIL COUNT          | ERROR COUNT = %0d", report_fail_count);
        $display("============================================================");
    end
endtask

task automatic log_final_error_summary;
    begin
        if (report_fd != 0) begin
            $fdisplay(report_fd, "============================================================");
            $fdisplay(report_fd, "FINAL TEST ERROR SUMMARY");
            $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
            $fdisplay(report_fd, "TEST2_REFRESH_CFG       = %0d cycles (0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
            $fdisplay(report_fd, "TEST 1 NORMAL_CONTIGUOUS_WRITE_READ | ERROR COUNT = %0d", test1_error_count);
            $fdisplay(report_fd, "TEST 2 WRITE_REQUEST_DURING_REFRESH_TRC | ERROR COUNT = %0d", test2_error_count);
            $fdisplay(report_fd, "TEST 3 NON_CONTIGUOUS_THEN_CONTIGUOUS | ERROR COUNT = %0d", test3_error_count);
            $fdisplay(report_fd, "TOTAL COMPARE FAIL COUNT          | ERROR COUNT = %0d", report_fail_count);
            $fdisplay(report_fd, "============================================================");
        end
    end
endtask

task automatic log_overflow_results;
    input [8*64-1:0] linear_name;
    input [8*64-1:0] observed_name;
    input integer start_bank;
    input integer start_row;
    input integer start_col;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    integer beat;
    integer linear_index;
    integer linear_bank;
    integer linear_row;
    integer linear_col;
    integer actual_bank;
    integer actual_row;
    integer actual_col;
    integer burst_group_base;
    reg [15:0] expected;
    begin
        for (beat = 0; beat < (TEST_WORD_COUNT * 2); beat = beat + 1) begin
            expected = pattern_halfword(beat, word0, word1, word2, word3);

            linear_index = ((((start_row * 4) + start_bank) * 512) + start_col) + beat;
            linear_col = linear_index % 512;
            linear_bank = (linear_index / 512) % 4;
            linear_row = linear_index / 2048;

            if (TEST_BL == 1) begin
                actual_bank = linear_bank;
                actual_row  = linear_row;
                actual_col  = linear_col;
            end else begin
                burst_group_base = start_col - (start_col % TEST_BL);
                actual_bank = start_bank;
                actual_row  = start_row;
                actual_col  = burst_group_base + ((start_col + beat) % TEST_BL);
            end

            log_expect_halfword(linear_name, linear_bank, linear_row, linear_col, expected, 0);
            log_expect_halfword(observed_name, actual_bank, actual_row, actual_col, expected, 1);
        end
    end
endtask

task automatic log_test_results;
    input [31:0] test_id;
    integer fail_before;
    integer local_fail_count;
    reg test_skipped;
    begin
        fail_before = report_fail_count;
        local_fail_count = 0;
        test_skipped = 1'b0;
        verbose_compare_console = 1'b1;
        case (test_id)
            32'd1: begin
                log_compare_words("TEST1_ADDR_A", 0, 2, 0,
                                  32'hBBBBAAAA, 32'hDDDDCCCC, 32'h22221111, 32'h44443333);
                log_compare_words("TEST1_ADDR_B", 0, 4, 0,
                                  32'hFFFF0000, 32'hA55A55AA, 32'h56781234, 32'hDEF09ABC);
            end
            32'd2: begin
                log_compare_words("TEST2_ADDR_A", 0, 12, 0,
                                  32'h0F0FF0F0, 32'hA1B2C3D4, 32'h11223344, 32'h99AABBCC);
            end
            32'd3: begin
                log_compare_single_word("TEST3_ADDR0", 0, 8, 0,  32'h13579BDF);
                log_compare_masked_halfword("TEST3_MASK0", 0, 8, 2);
                log_compare_masked_halfword("TEST3_MASK0", 0, 8, 3);
                log_compare_single_word("TEST3_ADDR1", 0, 8, 8,  32'hCAFEBABE);
                log_compare_masked_halfword("TEST3_MASK1", 0, 8, 10);
                log_compare_masked_halfword("TEST3_MASK1", 0, 8, 11);
                log_compare_single_word("TEST3_ADDR2", 0, 8, 16, 32'h10203040);
                log_compare_single_word("TEST3_ADDR3", 0, 8, 18, 32'h55667788);
            end
        endcase

        local_fail_count = report_fail_count - fail_before;

        case (test_id)
            32'd1: test1_error_count = local_fail_count;
            32'd2: test2_error_count = local_fail_count;
            32'd3: test3_error_count = local_fail_count;
        endcase

        if (test_skipped) begin
            $display("[%0t] TEST %0d CHECK | CLK1=%0d BL=%0d CL=%0d | RESULT=SKIPPED",
                     $time, test_id, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            if (report_fd != 0)
                $fdisplay(report_fd, "TEST %0d CHECK SUMMARY | CLK1=%0d BL=%0d CL=%0d | RESULT=SKIPPED",
                          test_id, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
        end else begin
            $display("[%0t] TEST %0d CHECK | CLK1=%0d BL=%0d CL=%0d | RESULT=%0s",
                     $time, test_id, CLK1_FREQ_MHZ, TEST_BL, TEST_CL,
                     (report_fail_count == fail_before) ? "PASS" : "FAIL");
            if (report_fd != 0)
                $fdisplay(report_fd, "TEST %0d CHECK SUMMARY | CLK1=%0d BL=%0d CL=%0d | RESULT=%0s",
                          test_id, CLK1_FREQ_MHZ, TEST_BL, TEST_CL,
                          (report_fail_count == fail_before) ? "PASS" : "FAIL");
        end

        verbose_compare_console = 1'b0;
    end
endtask

task automatic log_test_event_report;
    input [31:0] test_id;
    input [31:0] test_state;
    begin
        if (report_fd != 0) begin
            case (test_id)
                32'd1: begin
                    if (test_state == FW_TEST_STATE_START) begin
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 1 : NORMAL_CONTIGUOUS_WRITE_READ");
                        $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                        $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 1 START : NORMAL_CONTIGUOUS_WRITE_READ");
                    end
                    else if (test_state == FW_TEST_STATE_DONE) $fdisplay(report_fd, "TEST 1 DONE  : NORMAL_CONTIGUOUS_WRITE_READ");
                end
                32'd2: begin
                    if (test_state == FW_TEST_STATE_START) begin
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 2 : WRITE_REQUEST_DURING_REFRESH_TRC");
                        $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                        $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
                        $fdisplay(report_fd, "TEST2_REFRESH_CFG_USED   = FORCED (%0d cycles, 0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 2 START : WRITE_REQUEST_DURING_REFRESH_TRC");
                    end
                    else if (test_state == FW_TEST_STATE_DONE) $fdisplay(report_fd, "TEST 2 DONE  : WRITE_REQUEST_DURING_REFRESH_TRC");
                end
                32'd3: begin
                    if (test_state == FW_TEST_STATE_START) begin
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 3 : NON_CONTIGUOUS_THEN_CONTIGUOUS");
                        $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                        $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
                        $fdisplay(report_fd, "============================================================");
                        $fdisplay(report_fd, "TEST 3 START : NON_CONTIGUOUS_THEN_CONTIGUOUS");
                    end
                    else if (test_state == FW_TEST_STATE_DONE) $fdisplay(report_fd, "TEST 3 DONE  : NON_CONTIGUOUS_THEN_CONTIGUOUS");
                end
            endcase
        end
    end
endtask

task automatic print_test_header;
    input [31:0] test_id;
    input [8*64-1:0] test_name;
    begin
        $display("============================================================");
        $display("[%0t] TEST %0d : %0s", $time, test_id, test_name);
        $display("CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
        $display("DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
        if (test_id == 2)
            $display("TEST2_REFRESH_CFG_USED   = FORCED (%0d cycles, 0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
        $display("============================================================");
    end
endtask

task automatic log_test_header_report;
    input [31:0] test_id;
    input [8*64-1:0] test_name;
    begin
        if (report_fd != 0) begin
            $fdisplay(report_fd, "============================================================");
            $fdisplay(report_fd, "TEST %0d : %0s", test_id, test_name);
            $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
            if (test_id == 2)
                $fdisplay(report_fd, "TEST2_REFRESH_CFG_USED   = FORCED (%0d cycles, 0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
            $fdisplay(report_fd, "============================================================");
        end
    end
endtask

task automatic print_test_event;
    input [31:0] test_id;
    input [31:0] test_state;
    begin
        case (test_id)
            32'd1: begin
                if (test_state == FW_TEST_STATE_START) begin
                    print_test_header(1, "NORMAL_CONTIGUOUS_WRITE_READ");
                    $display("[%0t] TEST 1 START : NORMAL_CONTIGUOUS_WRITE_READ | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                end
                else if (test_state == FW_TEST_STATE_DONE) $display("[%0t] TEST 1 DONE  : NORMAL_CONTIGUOUS_WRITE_READ | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            end
            32'd2: begin
                if (test_state == FW_TEST_STATE_START) begin
                    print_test_header(2, "WRITE_REQUEST_DURING_REFRESH_TRC");
                    $display("[%0t] TEST 2 START : WRITE_REQUEST_DURING_REFRESH_TRC | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                end
                else if (test_state == FW_TEST_STATE_DONE) $display("[%0t] TEST 2 DONE  : WRITE_REQUEST_DURING_REFRESH_TRC | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            end
            32'd3: begin
                if (test_state == FW_TEST_STATE_START) begin
                    print_test_header(3, "NON_CONTIGUOUS_THEN_CONTIGUOUS");
                    $display("[%0t] TEST 3 START : NON_CONTIGUOUS_THEN_CONTIGUOUS | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
                end
                else if (test_state == FW_TEST_STATE_DONE) $display("[%0t] TEST 3 DONE  : NON_CONTIGUOUS_THEN_CONTIGUOUS | CLK1=%0d BL=%0d CL=%0d", $time, CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
            end
        endcase
    end
endtask

//================================================================
// Log
//================================================================
  
initial begin
    $timeformat(-9, 1, " ns", 10);

    cycles = 0;
    last_test_id = 32'd0;
    last_test_state = FW_TEST_STATE_IDLE;
    last_test_event = 32'd0;
    report_fail_count = 0;
    test1_error_count = 0;
    test2_error_count = 0;
    test3_error_count = 0;
    test4_error_count = 0;
    test5_error_count = 0;
    test6_error_count = 0;
    test8_error_count = 0;
    test9_error_count = 0;
    test8_skipped = 1'b0;
    test2_track_active = 1'b0;
    test2_refresh_start_time = 0;
    test2_refresh_window_time = 0;
    test2_cmd_during_trc_time = 0;
    test2_actual_write_time = 0;
    test2_cmd_during_trc = 1'b0;
    test2_mem_wr_req_sync = 2'b00;

    if (!$value$plusargs("REPORT_FILE=%s", report_path))
        report_path = "report/tb_cpu_report.log";

    report_fd = $fopen(report_path, "w");

    $display("============================================================");
    $display("CPU SDRAM REPORT");
    $display("CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
    $display("DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
    $display("TEST2_REFRESH_CFG       = %0d cycles (0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
    $display("============================================================");

    if (report_fd != 0) begin
        $fdisplay(report_fd, "============================================================");
        $fdisplay(report_fd, "CPU SDRAM REPORT");
        $fdisplay(report_fd, "CONFIG : CLK1=%0d MHz, BL=%0d, CL=%0d", CLK1_FREQ_MHZ, TEST_BL, TEST_CL);
        $fdisplay(report_fd, "DEFAULT_AUTO_REFRESH_CFG = %0d cycles (0x%08h)", TEST_REFRESH_PERIOD, TEST_REFRESH_PERIOD);
        $fdisplay(report_fd, "TEST2_REFRESH_CFG       = %0d cycles (0x%08h)", TEST2_REFRESH_CFG, TEST2_REFRESH_CFG);
        $fdisplay(report_fd, "============================================================");
    end

    while (cycles < 400000) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;

        curr_test_id = u_dut.uAHB2MEM.memory[FW_TEST_ID_IDX];
        curr_test_state = u_dut.uAHB2MEM.memory[FW_TEST_STATE_IDX];
        curr_test_event = u_dut.uAHB2MEM.memory[FW_TEST_EVENT_IDX];

        if (curr_test_event != last_test_event) begin
            if ((curr_test_event[31:16] != 16'd0) && (curr_test_event[15:0] != FW_TEST_STATE_IDLE)) begin
                if ((curr_test_event[31:16] == 16'd2) && (curr_test_event[15:0] == FW_TEST_STATE_START)) begin
                    test2_track_active = 1'b1;
                    test2_refresh_start_time = 0;
                    test2_refresh_window_time = 0;
                    test2_cmd_during_trc_time = 0;
                    test2_actual_write_time = 0;
                    test2_cmd_during_trc = 1'b0;
                end
                print_test_event(curr_test_event[31:16], curr_test_event[15:0]);
                log_test_event_report(curr_test_event[31:16], curr_test_event[15:0]);
                if (curr_test_event[15:0] == FW_TEST_STATE_DONE) begin
                    if (curr_test_event[31:16] == 16'd2) begin
                        test2_track_active = 1'b0;
                        log_test2_refresh_summary;
                    end
                    log_test_results(curr_test_event[31:16]);
                end
            end
            last_test_event = curr_test_event;
        end

        if ((curr_test_id != last_test_id) || (curr_test_state != last_test_state)) begin
            last_test_id = curr_test_id;
            last_test_state = curr_test_state;
        end

        if (u_dut.uAHB2MEM.memory[FW_STATUS_IDX] == FW_STATUS_PASS) begin
            dump_readbacks;
            print_final_error_summary;
            $display("[%0t] CPU SDRAM test PASS", $time);
            if (report_fd != 0) begin
                log_final_error_summary;
                $fdisplay(report_fd, "FW STATUS = 0x%08h", u_dut.uAHB2MEM.memory[FW_STATUS_IDX]);
                $fdisplay(report_fd, "FW ERROR  = 0x%08h", u_dut.uAHB2MEM.memory[FW_ERROR_IDX]);
                $fdisplay(report_fd, "FINAL STATUS : PASS");
                $fdisplay(report_fd, "COMPARE STATUS = %0s", (report_fail_count == 0) ? "PASS" : "FAIL");
                $fdisplay(report_fd, "COMPARE FAIL COUNT = %0d", report_fail_count);
                $fclose(report_fd);
            end
            $finish;
        end

        if ((u_dut.uAHB2MEM.memory[FW_STATUS_IDX] & 32'hFFFF0000) == FW_STATUS_FAIL) begin
            dump_readbacks;
            print_final_error_summary;
            $display("[%0t] CPU SDRAM test FAIL", $time);
            if (report_fd != 0) begin
                log_final_error_summary;
                $fdisplay(report_fd, "FW STATUS = 0x%08h", u_dut.uAHB2MEM.memory[FW_STATUS_IDX]);
                $fdisplay(report_fd, "FW ERROR  = 0x%08h", u_dut.uAHB2MEM.memory[FW_ERROR_IDX]);
                $fdisplay(report_fd, "FINAL STATUS : FAIL");
                $fdisplay(report_fd, "COMPARE STATUS = %0s", (report_fail_count == 0) ? "PASS" : "FAIL");
                $fdisplay(report_fd, "COMPARE FAIL COUNT = %0d", report_fail_count);
                $fclose(report_fd);
            end
            $finish;
        end
    end

    dump_readbacks;
    print_final_error_summary;
    $display("[%0t] CPU SDRAM test TIMEOUT", $time);
    if (report_fd != 0) begin
        log_final_error_summary;
        $fdisplay(report_fd, "FW STATUS = 0x%08h", u_dut.uAHB2MEM.memory[FW_STATUS_IDX]);
        $fdisplay(report_fd, "FW ERROR  = 0x%08h", u_dut.uAHB2MEM.memory[FW_ERROR_IDX]);
        $fdisplay(report_fd, "FINAL STATUS : TIMEOUT");
        $fdisplay(report_fd, "COMPARE STATUS = %0s", (report_fail_count == 0) ? "PASS" : "FAIL");
        $fdisplay(report_fd, "COMPARE FAIL COUNT = %0d", report_fail_count);
        $fclose(report_fd);
    end
    $finish;
end

always @(posedge CLK1 or negedge reset_n) begin
    if (!reset_n) begin
        test2_mem_wr_req_sync <= 2'b00;
        test2_refresh_start_time <= 0;
        test2_refresh_window_time <= 0;
        test2_cmd_during_trc_time <= 0;
        test2_actual_write_time <= 0;
        test2_cmd_during_trc <= 1'b0;
    end else begin
        test2_mem_wr_req_sync <= {test2_mem_wr_req_sync[0], u_dut.uAPBSYS.u_dut.u_apb_slave.mem_wr_req};

        if (test2_track_active) begin
            if (!test2_cmd_during_trc &&
                (u_dut.uAPBSYS.u_dut.u_ctrl.state == 4'd6) &&
                (u_dut.uAPBSYS.u_dut.u_ctrl.state_d != 4'd6)) begin
                test2_refresh_start_time <= $time;
            end

            if (!test2_cmd_during_trc &&
                (u_dut.uAPBSYS.u_dut.u_ctrl.state == 4'd6) &&
                test2_mem_wr_req_sync[1]) begin
                test2_refresh_window_time <= $time;
                test2_cmd_during_trc_time <= $time;
                test2_cmd_during_trc <= 1'b1;
            end

            if ((test2_cmd_during_trc_time != 0) && (test2_actual_write_time == 0) &&
                !cs && ras && !cas && !we_sdram) begin
                test2_actual_write_time <= $time;
            end
        end
    end
end

endmodule
