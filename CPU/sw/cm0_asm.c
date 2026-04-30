/* Register map (sdram_apb_master_rw.v localparam) */
#define sdram_mrs_val  (*(volatile unsigned long *)0x50000000)
#define sdram_timing   (*(volatile unsigned long *)0x50000004)
#define sdram_refresh  (*(volatile unsigned long *)0x50000008)
#define sdram_status   (*(volatile unsigned long *)0x50000010)

/* Firmware mailbox observed by tb_cpu.v */
#define fw_status      (*(volatile unsigned long *)0x00000F00)
#define fw_error       (*(volatile unsigned long *)0x00000F04)
#define fw_test_id     (*(volatile unsigned long *)0x00000F08)
#define fw_test_state  (*(volatile unsigned long *)0x00000F0C)
#define fw_test_event  (*(volatile unsigned long *)0x00000F10)

#define FW_STATUS_PASS 0x600D0001UL
#define FW_TEST_STATE_IDLE   0UL
#define FW_TEST_STATE_START  1UL
#define FW_TEST_STATE_DONE   2UL

/* CPU-reachable SDRAM window (current AHB decode: 16MB = 0x60000000 ~ 0x60FFFFFF) */
#define sdram_row1  ((volatile unsigned long *)0x60002000)
#define sdram_row2  ((volatile unsigned long *)0x60004000)

/* ================================================================
 *  [1] User config
 *  Only grade -6 is supported now.
 *  CL      : 2 or 3
 *  BL      : 1, 2, 4, 8
 *  CLK_MHZ : 133 or 166 MHz
 * ================================================================ */
#ifndef cl
#define cl       3
#endif

#ifndef bl
#define bl       4
#endif

#ifndef clk_mhz
#define clk_mhz  166
#endif

/* ================================================================
 *  Timing spec for grade -6
 * ================================================================ */
#define spec_tRC_ns        60
#define spec_tRCD_ns       18
#define spec_tRP_ns        18
#define spec_refresh_ms    64
#define spec_refresh_rows  8192
#define spec_init_wait_ns  200000

/* ================================================================
 *  Timing value
 * ================================================================ */
/* Convert ns to clock cycles 
 * ex. 60ns @ 166MHz: ceil(60 * 166 / 1000) = 10 clk */
#define ns_to_clk(ns)  (((unsigned long)(ns) * (unsigned long)clk_mhz + 999) / 1000)

/* Convert refresh interval to clock cycles.
 * 8192 rows must be refreshed within 64ms, so @166MHz:
 per refresh = clkMHz/8192 -> clock cycle = per refresh*clk MHz */
// #define refresh_to_clk(ms, rows)  ((((unsigned long)(ms) * (unsigned long)clk_mhz * 1000) + (unsigned long)(rows) - 1) / (unsigned long)(rows))

#define tRC_val        ns_to_clk(spec_tRC_ns)       /* 60ns     -> 10 clk */
#define tRCD_val       ns_to_clk(spec_tRCD_ns)      /* 18ns     ->  3 clk */
#define tRP_val        ns_to_clk(spec_tRP_ns)       /* 18ns     ->  3 clk */
#define init_wait_val  ns_to_clk(spec_init_wait_ns) /* 200000ns -> 33200 clk */

// #define refresh_period_val  refresh_to_clk(spec_refresh_ms, spec_refresh_rows)
#define refresh_period_val  (((64UL * clk_mhz * 1000) + 8191) / 8192)
/* timing_value bit packing
 * [30]    = 1         : init start trigger
 * [29:26] = tRP_val   : precharge time       (4-bit)
 * [25:22] = tRCD_val  : ACTIVE to READ/WRITE (4-bit)
 * [21:16] = tRC_val   : RAS cycle time       (6-bit)
 * [15:0]  = init_wait : power-up 200us wait  (16-bit) */
#define timing_value  (((unsigned long)1 << 30) | ((unsigned long)(tRP_val & 0xF) << 26) | ((unsigned long)(tRCD_val & 0xF) << 22) | ((unsigned long)(tRC_val & 0x3F) << 16) | ((unsigned long)(init_wait_val) & 0xFFFF))

/* ================================================================
 *  Mode register value
 * ================================================================ */
/* BL encoding: BL=1->000, BL=2->001, BL=4->010, BL=8->011 */
#if   bl == 1
  #define bl_enc  0
#elif bl == 2
  #define bl_enc  1
#elif bl == 4
  #define bl_enc  2
#else
  #define bl_enc  3
#endif

/* CL encoding matches value: CL2->2, CL3->3 */
#if cl == 2
  #define cl_enc  2
#else
  #define cl_enc  3
#endif

/* MRS bit packing
 * [6:4] = cl_enc : CAS latency
 * [3]   = 0      : sequential burst
 * [2:0] = bl_enc : burst length */
#define mrs_value  (((unsigned long)cl_enc << 4) | ((unsigned long)0 << 3) | ((unsigned long)bl_enc))

/* ================================================================
 *  Test scenario
 * =============================================================== */
#define status_init_done_mask  1UL
#define status_busy_mask       2UL

#if bl == 8
  #define test_word_count  4
#elif bl == 4
  #define test_word_count  2
#else
  #define test_word_count  1
#endif

#define boundary_start_col  (512UL - (test_word_count * 2UL))
#define overflow_start_col  (512UL - test_word_count)
#define row_word_count      256UL

/* SDRAM address helper: row[12:0], bank[1:0], col[8:0] in halfword units */
#define sdram_addr(row, bank, col) \
    ((volatile unsigned long *)(0x60000000 + (((((unsigned long)(row) << 11) | ((unsigned long)(bank) << 9) | (unsigned long)(col))) << 1)))

#define test1_addr_a      sdram_addr(2,  0, 0)
#define test1_addr_b      sdram_addr(4,  0, 0)
#define test2_addr_a      sdram_addr(12, 0, 0)
#define test2_addr_b      sdram_addr(14, 1, 0)
#define test2_refresh_cfg 64UL
#define test2_apply_delay 64UL
#define test2_repeat_count 8UL
#define test2_base_data   0xA5000000UL
#define test3_addr0       sdram_addr(8,  0, 0)
#define test3_addr1       sdram_addr(8,  0, 8)
#define test3_addr2       sdram_addr(8,  0, 16)
#define test3_addr3       sdram_addr(8,  0, 18)
#define test3_idle_delay  1024UL

unsigned long test1_pattern_a[4] = {
    0xBBBBAAAA, 0xDDDDCCCC,
    0x22221111, 0x44443333
};
unsigned long test1_pattern_b[4] = {
    0xFFFF0000, 0xA55A55AA,
    0x56781234, 0xDEF09ABC
};
unsigned long test2_pattern_a[4] = {
    0x0F0FF0F0, 0xA1B2C3D4,
    0x11223344, 0x99AABBCC
};
unsigned long test2_pattern_b[4] = {
    0x55AA33CC, 0x12345678,
    0x87654321, 0xCC33AA55
};
#define test3_data0  0x13579BDFUL
#define test3_data1  0xCAFEBABEUL
#define test3_data2  0x10203040UL
#define test3_data3  0x55667788UL

volatile unsigned long read_sink;

//sram -> sdram
void burst_write(volatile unsigned long *base, const unsigned long *pattern)
{
    unsigned long i;

    for (i = 0; i < test_word_count; i++) {
        base[i] = pattern[i];
    }
}

// sdram ->sram
void burst_read(volatile unsigned long *base)
{
    unsigned long i;

    for (i = 0; i < test_word_count; i++) {
        read_sink = base[i];
    }
}

void burst_write_constant(volatile unsigned long *base, unsigned long value)
{
    unsigned long i;

    for (i = 0; i < test_word_count; i++) {
        base[i] = value;
    }
}

void word_write(volatile unsigned long *addr, unsigned long value)
{
    *addr = value;
}

void word_read(volatile unsigned long *addr)
{
    read_sink = *addr;
}

void row_span_write_auto(unsigned long row,
                         unsigned long bank,
                         unsigned long start_col,
                         unsigned long word_count,
                         unsigned long base_value)
{
    volatile unsigned long *base = sdram_addr(row, bank, start_col);
    unsigned long i;

    for (i = 0UL; i < word_count; i++) {
        base[i] = base_value + i;
    }
}

void row_span_read_auto(unsigned long row,
                        unsigned long bank,
                        unsigned long start_col,
                        unsigned long word_count)
{
    volatile unsigned long *base = sdram_addr(row, bank, start_col);
    unsigned long i;

    for (i = 0UL; i < word_count; i++) {
        read_sink = base[i];
    }
}

void row_fill_auto(unsigned long row, unsigned long bank, unsigned long base_value)
{
    row_span_write_auto(row, bank, 0UL, row_word_count, base_value);
}

void row_read_auto(unsigned long row, unsigned long bank)
{
    row_span_read_auto(row, bank, 0UL, row_word_count);
}

void delay_loop(unsigned long count)
{
    while (count != 0UL) {
        read_sink = count;
        count--;
    }
}

void wait_sdram_idle(void)
{
    while (sdram_status & status_busy_mask) {}
}

void write_refresh_checked(unsigned long value)
{
    do {
        sdram_refresh = value;
    } while (sdram_refresh != value);
}

void report_test_start(unsigned long test_id)
{
    fw_test_id = test_id;
    fw_test_state = FW_TEST_STATE_START;
    fw_test_event = (test_id << 16) | FW_TEST_STATE_START;
}

void report_test_done(unsigned long test_id)
{
    fw_test_id = test_id;
    fw_test_state = FW_TEST_STATE_DONE;
    fw_test_event = (test_id << 16) | FW_TEST_STATE_DONE;
}

void immediate_write_read(volatile unsigned long *base, const unsigned long *pattern)
{
    unsigned long i;

    for (i = 0; i < test_word_count; i++) {
        base[i] = pattern[i];
    }

    for (i = 0; i < test_word_count; i++) {
        read_sink = base[i];
    }
}

void test1(void)
{
    burst_write(test1_addr_a, test1_pattern_a);
    burst_write(test1_addr_b, test1_pattern_b);
    burst_read(test1_addr_a);
    burst_read(test1_addr_b);
}

void test2(void)
{
    unsigned long saved_refresh;
    unsigned long i;

    saved_refresh = sdram_refresh;
    write_refresh_checked(test2_refresh_cfg);
    delay_loop(test2_apply_delay);

    for (i = 0UL; i < test2_repeat_count; i++) {
        burst_write(test2_addr_a, test2_pattern_a);
    }
    burst_read(test2_addr_a);

    write_refresh_checked(saved_refresh);
    delay_loop(test2_apply_delay);
}

void test3(void)
{
    word_write(test3_addr0, test3_data0);
    word_write(test3_addr1, test3_data1);
    word_write(test3_addr2, test3_data2);
    word_write(test3_addr3, test3_data3);
    delay_loop(test3_idle_delay);
    word_read(test3_addr0);
    word_read(test3_addr1);
    word_read(test3_addr2);
    word_read(test3_addr3);
}

int main(void)
{
    fw_status = 0;
    fw_error  = 0;
    fw_test_id = 0;
    fw_test_state = FW_TEST_STATE_IDLE;
    read_sink = 0;

    sdram_mrs_val = mrs_value;
    sdram_refresh = refresh_period_val;
    sdram_timing  = timing_value;

    while (!(sdram_status & status_init_done_mask)) {} /* wait until init_done = 1 */

    report_test_start(1UL);
    test1();
    report_test_done(1UL);

    report_test_start(2UL);
    test2();
    report_test_done(2UL);

    report_test_start(3UL);
    test3();
    report_test_done(3UL);

    fw_error  = 0;
    fw_status = FW_STATUS_PASS;

    while (1) {}
}
