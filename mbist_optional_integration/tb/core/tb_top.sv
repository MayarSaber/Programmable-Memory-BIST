// Copyright 2017 Embecosm Limited <www.embecosm.com>
// Copyright 2018 Robert Balas <balasr@student.ethz.ch>
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Top level wrapper for a RI5CY testbench
// Contributor: Robert Balas <balasr@student.ethz.ch>
//              Jeremy Bennett <jeremy.bennett@embecosm.com>

module tb_top
    #(parameter INSTR_RDATA_WIDTH = 128,
      parameter RAM_ADDR_WIDTH = 22,
      parameter BOOT_ADDR  = 'h80);

    // comment to record execution trace
    `define TRACE_EXECUTION

    const time CLK_PHASE_HI       = 5ns;
    const time CLK_PHASE_LO       = 5ns;
    const time CLK_PERIOD         = CLK_PHASE_HI + CLK_PHASE_LO;
    const time STIM_APPLICATION_DEL = CLK_PERIOD * 0.1;
    const time RESP_ACQUISITION_DEL = CLK_PERIOD * 0.9;
    const time RESET_DEL = STIM_APPLICATION_DEL;
    const int  RESET_WAIT_CYCLES  = 4;


    // clock and reset for tb
    logic                   clk   = 'b1;
    logic                   rst_n = 'b0;

    // cycle counter
    int unsigned            cycle_cnt_q;

    // testbench result
    logic                   tests_passed;
    logic                   tests_failed;
    logic                   exit_valid;
    logic [31:0]            exit_value;

    // signals for ri5cy
    logic                   fetch_enable = 1'b0;

    // MBIST CSR signals (power-on self-test)
    logic                   mbist_csr_we;
    logic                   mbist_csr_re;
    logic [7:0]             mbist_csr_addr;
    logic [31:0]            mbist_csr_wdata;
    logic [31:0]            mbist_csr_rdata;

    // allow vcd dump
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("riscy_tb.vcd");
            $dumpvars(0, tb_top);
        end
    end

    // we either load the provided firmware or execute a small test program that
    // doesn't do more than an infinite loop with some I/O
    // Firmware file (loaded AFTER power-on MBIST)
string firmware;

initial begin : get_firmware_arg
    if(!$value$plusargs("firmware=%s", firmware)) begin
        $display("No firmware specified (+firmware=...)");
        $finish;
    end
end

// --------------------------------------------------------------------
// Option B: Power-on MBIST
// 1) Hold fetch_enable low (core stays idle)
// 2) After reset deassert, start MBIST through CSR
// 3) Wait for DONE/PASS
// 4) Load firmware into dp_ram
// 5) Enable fetch and run normal functional test
// --------------------------------------------------------------------
task automatic mbist_csr_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge clk);
    mbist_csr_addr  <= addr;
    mbist_csr_wdata <= data;
    mbist_csr_we    <= 1'b1;
    mbist_csr_re    <= 1'b0;
    @(posedge clk);
    mbist_csr_we    <= 1'b0;
    mbist_csr_addr  <= '0;
    mbist_csr_wdata <= '0;
endtask

task automatic mbist_csr_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge clk);
    mbist_csr_addr <= addr;
    mbist_csr_we   <= 1'b0;
    mbist_csr_re   <= 1'b1;
    #1ps; // allow combinational csr_rdata to settle
    data = mbist_csr_rdata;
    @(posedge clk);
    mbist_csr_re   <= 1'b0;
    mbist_csr_addr <= '0;
endtask

initial begin : power_on_mbist_sequence
    logic [31:0] status;
    logic [31:0] ctrl;
    int unsigned mbist_end;
    int unsigned algo_sel;

    // default config: test first 16KB so simulation stays fast
    mbist_end = 32'h0000_3FFC; // 16KB - 4 (word aligned)
    if ($value$plusargs("mbist_end=%h", mbist_end)) begin end

    algo_sel = 0; // 0=MATS+ 1=MATS++ 2=March C-
    if ($value$plusargs("mbist_algo=%d", algo_sel)) begin end

    // init CSR strobes
    mbist_csr_we    = 1'b0;
    mbist_csr_re    = 1'b0;
    mbist_csr_addr  = '0;
    mbist_csr_wdata = '0;

    // keep core halted until MBIST is done and firmware is loaded
    fetch_enable = 1'b0;

    // wait for reset release
    wait (rst_n === 1'b1);
    @(posedge clk);

    if($test$plusargs("verbose")) begin
        $display("[MBIST] Starting power-on MBIST: start=0x%0h end=0x%0h algo=%0d", 32'h0, mbist_end, algo_sel);
    end

    // program range
    mbist_csr_write(8'h04, 32'h0000_0000);   // STARTADR
    mbist_csr_write(8'h08, mbist_end[31:0]); // ENDADR

    // CTRL: TEST_MODE=1, START=1, STOP_ON_FAIL=1, ALGO_SEL
    ctrl = 32'h0;
    ctrl[0]   = 1'b1;               // TEST_MODE
    ctrl[1]   = 1'b1;               // START
    ctrl[4]   = 1'b1;               // STOP_ON_FAIL
    ctrl[6:5] = algo_sel[1:0];      // ALGO_SEL
    mbist_csr_write(8'h00, ctrl);   // CTRL

    // poll STATUS until DONE
    do begin
        mbist_csr_read(8'h0C, status);
    end while (status[1] == 1'b0);

    if (status[3]) begin
        $display("[MBIST] FAIL (STATUS=0x%08x)", status);
        $fatal(1, "MBIST failed at power-on.");
    end else begin
        $display("[MBIST] PASS (STATUS=0x%08x)", status);
    end

    // now load firmware (MBIST already finished, so it won't overwrite it)
    if($test$plusargs("verbose"))
        $display("[TESTBENCH] %t: loading firmware %0s after MBIST ...", $time, firmware);
    $readmemh(firmware, riscv_wrapper_i.ram_i.dp_ram_i.mem);

    // start CPU
    fetch_enable = 1'b1;
    if($test$plusargs("verbose"))
        $display("[TESTBENCH] %t: fetch_enable asserted, CPU starts executing ...", $time);
end

    // clock generation
    initial begin: clock_gen
        forever begin
            #CLK_PHASE_HI clk = 1'b0;
            #CLK_PHASE_LO clk = 1'b1;
        end
    end: clock_gen

    // reset generation
    initial begin: reset_gen
        rst_n          = 1'b0;

        // wait a few cycles
        repeat (RESET_WAIT_CYCLES) begin
            @(posedge clk); //TODO: was posedge, see below
        end

        // start running
        #RESET_DEL rst_n = 1'b1;
        if($test$plusargs("verbose"))
            $display("reset deasserted", $time);

    end: reset_gen

    // set timing format
    initial begin: timing_format
        $timeformat(-9, 0, "ns", 9);
    end: timing_format

    // abort after n cycles, if we want to
    always_ff @(posedge clk, negedge rst_n) begin
        automatic int maxcycles;
        if($value$plusargs("maxcycles=%d", maxcycles)) begin
            if (!rst_n) begin
                cycle_cnt_q <= 0;
            end else begin
                cycle_cnt_q     <= cycle_cnt_q + 1;
                if (cycle_cnt_q >= maxcycles) begin
                    $display("[TB] Maxcycles reached -> finishing.");
                    $finish;
                end
            end
        end
    end

    // check if we succeded
    always_ff @(posedge clk, negedge rst_n) begin
        if (tests_passed) begin
            $display("ALL TESTS PASSED");
            $finish;
        end
        if (tests_failed) begin
            $display("TEST(S) FAILED!");
            $finish;
        end
        if (exit_valid) begin
            if (exit_value == 0)
                $display("EXIT SUCCESS");
            else
                $display("EXIT FAILURE: %d", exit_value);
            $finish;
        end
    end

    //PoliTo: Memory map check
    always_ff @(posedge clk, negedge rst_n) begin
	//if (tb_top.riscv_wrapper_i.riscv_core_i.load_store_unit_i.data_we_ex_i == 1'h1) begin
	if (tb_top.riscv_wrapper_i.data_req == 1'h1 && tb_top.riscv_wrapper_i.data_we == 1'h1) begin
	  if (tb_top.riscv_wrapper_i.riscv_core_i.load_store_unit_i.data_addr_o < 32'h200000 || tb_top.riscv_wrapper_i.riscv_core_i.load_store_unit_i.data_addr_o > 32'h240000) begin
		  $display("MEMORY MAP WARNING: Writing OUTSIDE DRAM at address %h, time %t", tb_top.riscv_wrapper_i.riscv_core_i.load_store_unit_i.data_addr_o, $realtime); 
	  end 
	end
    end

    // wrapper for riscv, the memory system and stdout peripheral
    riscv_wrapper
        #(.INSTR_RDATA_WIDTH (INSTR_RDATA_WIDTH),
          .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),
          .BOOT_ADDR (BOOT_ADDR),
          .PULP_SECURE (1))

    riscv_wrapper_i
        (.clk_i          ( clk          ),
         .rst_ni         ( rst_n        ),
         .fetch_enable_i ( fetch_enable ),
         .tests_passed_o ( tests_passed ),
         .tests_failed_o ( tests_failed ),
         .exit_valid_o   ( exit_valid   ),
         .exit_value_o   ( exit_value   ),

         .mbist_csr_we_i    ( mbist_csr_we    ),
         .mbist_csr_re_i    ( mbist_csr_re    ),
         .mbist_csr_addr_i  ( mbist_csr_addr  ),
         .mbist_csr_wdata_i ( mbist_csr_wdata ),
         .mbist_csr_rdata_o ( mbist_csr_rdata ));
    
    initial begin : stop_after_mbist_block
        if ($test$plusargs("stop_after_mbist")) begin
            wait (rst_n === 1'b1);

            // Pick ONE of these, depending on what exists in your hierarchy:
            // wait (riscv_wrapper_i.mbist_done_o === 1'b1);
            // or if you have busy:
            // wait (riscv_wrapper_i.mbist_busy_o === 1'b0);

            // If MBIST is deeper (example), do something like:
            // wait (riscv_wrapper_i.mbist_csr_wrap_i.mbist_done_o === 1'b1);

            $display("[TB] MBIST done -> finishing.");
            $finish;
        end
    end

`ifndef VERILATOR
    initial begin
        assert (INSTR_RDATA_WIDTH == 128 || INSTR_RDATA_WIDTH == 32)
            else $fatal("invalid INSTR_RDATA_WIDTH, choose 32 or 128");
    end
`endif

endmodule // tb_top
