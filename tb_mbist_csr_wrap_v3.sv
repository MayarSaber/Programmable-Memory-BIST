module tb_mbist_csr_wrap;

  logic clk, rst_n;

  // CSR bus
  logic        csr_we, csr_re;
  logic [7:0]  csr_addr;
  logic [31:0] csr_wdata;
  logic [31:0] csr_rdata;

  // Normal port (pretend CPU)
  logic        n_en_b, n_we_b;
  logic [7:0]  n_addr_b;
  logic [31:0] n_wdata_b, n_rdata_b;
  logic [3:0]  n_be_b;

  // RAM port (through wrapper)
  logic        ram_en_b, ram_we_b;
  logic [7:0]  ram_addr_b;
  logic [31:0] ram_wdata_b, ram_rdata_b;
  logic [3:0]  ram_be_b;

  // Port A (for clean fault injection)
  logic         en_a, we_a;
  logic [7:0]   addr_a;
  logic [31:0]  wdata_a;
  logic [127:0] rdata_a;
  logic [3:0]   be_a;

  // >>> FIX: declare these BEFORE the initial block executes anything
  logic [31:0] rd;
  logic [31:0] st, sig;
  logic [31:0] ea, ex, eg;

  // Clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // DUT: RAM
  dp_ram #(.ADDR_WIDTH(8), .INSTR_RDATA_WIDTH(128)) u_ram (
    .clk_i(clk),

    .en_a_i   (en_a),
    .addr_a_i (addr_a),
    .wdata_a_i(wdata_a),
    .rdata_a_o(rdata_a),
    .we_a_i   (we_a),
    .be_a_i   (be_a),

    .en_b_i   (ram_en_b),
    .addr_b_i (ram_addr_b),
    .wdata_b_i(ram_wdata_b),
    .rdata_b_o(ram_rdata_b),
    .we_b_i   (ram_we_b),
    .be_b_i   (ram_be_b)
  );

  // DUT: CSR wrapper + core
  mbist_csr_wrap #(.ADDR_WIDTH(8), .DATA_WIDTH(32), .MISR_WIDTH(16)) u_wrap (
    .clk(clk),
    .rst_n(rst_n),

    .csr_we(csr_we),
    .csr_re(csr_re),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),

    .n_en_b(n_en_b),
    .n_we_b(n_we_b),
    .n_addr_b(n_addr_b),
    .n_wdata_b(n_wdata_b),
    .n_be_b(n_be_b),
    .n_rdata_b(n_rdata_b),

    .ram_en_b(ram_en_b),
    .ram_we_b(ram_we_b),
    .ram_addr_b(ram_addr_b),
    .ram_wdata_b(ram_wdata_b),
    .ram_be_b(ram_be_b),
    .ram_rdata_b(ram_rdata_b)
  );

  // CSR addresses
  localparam [7:0] CTRL     = 8'h00;
  localparam [7:0] STARTADR = 8'h04;
  localparam [7:0] ENDADR   = 8'h08;
  localparam [7:0] STATUS   = 8'h0C;
  localparam [7:0] SIG      = 8'h10;
  localparam [7:0] ERRADR   = 8'h14;
  localparam [7:0] ERREXP   = 8'h18;
  localparam [7:0] ERRGOT   = 8'h1C;


  localparam [7:0] EXPSIG   = 8'h20;

  // CTRL bit fields (see mbist_csr_wrap_v3.sv)
  localparam int CTRL_TEST_MODE    = 0;
  localparam int CTRL_START        = 1;
  localparam int CTRL_STOP         = 2;
  localparam int CTRL_BG_ENABLE    = 3;
  localparam int CTRL_STOP_ON_FAIL = 4;
  localparam int CTRL_ALGO_LSB     = 5; // [6:5]
  localparam int CTRL_BGCOUNT_LSB  = 7; // [9:7]
  localparam int CTRL_SIG_CHECK_EN = 10;

  // STATUS bit fields (see mbist_csr_wrap_v3.sv)
  localparam int ST_BUSY         = 0;
  localparam int ST_DONE         = 1;
  localparam int ST_PASS         = 2;
  localparam int ST_FAIL         = 3;
  localparam int ST_ABORTED      = 4;
  localparam int ST_ERR_VALID    = 5;
  localparam int ST_SIG_MISMATCH = 6;
  localparam int ST_TAKEOVER     = 7;
  // --------------------------
  // helpers
  // --------------------------
  task automatic csr_write(input [7:0] a, input [31:0] d);
    begin
      csr_addr  = a;
      csr_wdata = d;
      csr_we    = 1'b1;
      csr_re    = 1'b0;
      @(posedge clk);
      csr_we    = 1'b0;
    end
  endtask

  task automatic csr_read(input [7:0] a, output [31:0] d);
    begin
      csr_addr = a;
      csr_re   = 1'b1;
      csr_we   = 1'b0;
      @(posedge clk);
      d = csr_rdata;
      csr_re = 1'b0;
    end
  endtask

  task automatic normal_write_word(input [7:0] a, input [31:0] d);
    begin
      n_addr_b  = a;
      n_wdata_b = d;
      n_be_b    = 4'hF;
      n_en_b    = 1'b1;
      n_we_b    = 1'b1;
      @(posedge clk);
      n_en_b    = 1'b0;
      n_we_b    = 1'b0;
    end
  endtask

  task automatic normal_read_word(input [7:0] a, output [31:0] d);
    begin
      n_addr_b = a;
      n_be_b   = 4'hF;
      n_en_b   = 1'b1;
      n_we_b   = 1'b0;
      @(posedge clk);
      @(posedge clk);
      d = n_rdata_b;
      n_en_b = 1'b0;
    end
  endtask

  // Clean “byte write” via port A using byte-enables
  task automatic portA_write_byte(input [7:0] byte_addr, input [7:0] byte_val);
    logic [7:0] addr_aligned;
    logic [1:0] lane;
    begin
      lane = byte_addr[1:0];
      addr_aligned = {byte_addr[7:2], 2'b00};

      addr_a  = addr_aligned;
      wdata_a = 32'h0;
      wdata_a[8*lane +: 8] = byte_val;
      be_a    = (4'b0001 << lane);

      en_a    = 1'b1;
      we_a    = 1'b1;
      @(posedge clk);
      en_a    = 1'b0;
      we_a    = 1'b0;
      be_a    = 4'h0;
    end
  endtask

  task automatic do_reset();
    begin
      rst_n = 1'b0;

      csr_we = 0; csr_re = 0; csr_addr = 0; csr_wdata = 0;
      n_en_b = 0; n_we_b = 0; n_addr_b = 0; n_wdata_b = 0; n_be_b = 0;
      en_a = 0; we_a = 0; addr_a = 0; wdata_a = 0; be_a = 0;

      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  task automatic wait_done(input int unsigned max_cycles = 20000);
    logic [31:0] st_loc;
    int unsigned cyc;
    begin
      cyc = 0;
      do begin
        csr_read(STATUS, st_loc);
        cyc++;
        if (cyc >= max_cycles) begin
          $fatal(1, "[TB] TIMEOUT waiting for DONE. STATUS=0x%08x", st_loc);
        end
      end while (st_loc[1] == 1'b0);
    end
  endtask

  // ------------------------------------------------------------
  // Design Test
  // ------------------------------------------------------------

  task automatic banner(input string title);
    $display("\n============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic report_mbist(input string tag);
    csr_read(STATUS, st);
    csr_read(SIG,    sig);

    $display("[%s] STATUS: busy=%0d done=%0d pass=%0d fail=%0d aborted=%0d err_valid=%0d sig_mismatch=%0d takeover=%0d",
             tag,
             st[ST_BUSY], st[ST_DONE], st[ST_PASS], st[ST_FAIL], st[ST_ABORTED],
             st[ST_ERR_VALID], st[ST_SIG_MISMATCH], st[ST_TAKEOVER]);
    $display("[%s] SIG:    0x%04x", tag, sig[15:0]);

    if (st[ST_ERR_VALID]) begin
      csr_read(ERRADR, ea);
      csr_read(ERREXP, ex);
      csr_read(ERRGOT, eg);
      $display("[%s] ERR:    addr=0x%08x exp=0x%08x got=0x%08x", tag, ea, ex, eg);
    end
  endtask

  function automatic [31:0] make_ctrl(
      input logic test_mode,
      input logic start,
      input logic stop,
      input logic bg_enable,
      input logic stop_on_fail,
      input logic [1:0] algo,
      input logic [2:0] bg_count,
      input logic sig_check_en
  );
    make_ctrl = 32'h0;
    make_ctrl[CTRL_TEST_MODE]    = test_mode;
    make_ctrl[CTRL_START]        = start;
    make_ctrl[CTRL_STOP]         = stop;
    make_ctrl[CTRL_BG_ENABLE]    = bg_enable;
    make_ctrl[CTRL_STOP_ON_FAIL] = stop_on_fail;
    make_ctrl[CTRL_ALGO_LSB +: 2]    = algo;
    make_ctrl[CTRL_BGCOUNT_LSB +: 3] = bg_count;
    make_ctrl[CTRL_SIG_CHECK_EN] = sig_check_en;
  endfunction

  task automatic run_mbist(
      input string name,
      input logic [31:0] start_adr,
      input logic [31:0] end_adr,
      input logic [1:0]  algo,
      input logic        bg_enable,
      input logic [2:0]  bg_count,
      input logic        stop_on_fail,
      input logic        sig_check_en,
      input logic [15:0] exp_sig_16
  );
    time t0, t1;

    banner({"TEST: ", name});

    // Program range
    csr_write(STARTADR, start_adr);
    csr_write(ENDADR,   end_adr);

    // Optional signature check
    if (sig_check_en) begin
      csr_write(EXPSIG, {16'h0, exp_sig_16});
    end

    // Start
    t0 = $time;
    csr_write(CTRL, make_ctrl(1'b1, 1'b1, 1'b0, bg_enable, stop_on_fail, algo, bg_count, sig_check_en));

    // Show takeover while busy (sample a few cycles)
    repeat (5) begin
      @(posedge clk);
      csr_read(STATUS, st);
      if (st[ST_BUSY]) $display("  (during run) takeover=%0d busy=%0d", st[ST_TAKEOVER], st[ST_BUSY]);
    end

    wait_done();
    t1 = $time;

    report_mbist(name);
    $display("[%s] Duration: %0t ns", name, (t1 - t0));
  endtask

  // Helper: start MBIST then abort it mid-run
  task automatic run_and_abort(
      input string name,
      input logic [31:0] start_adr,
      input logic [31:0] end_adr,
      input logic [1:0]  algo,
      input int unsigned abort_after_cycles
  );
    banner({"TEST: ", name});
    csr_write(STARTADR, start_adr);
    csr_write(ENDADR,   end_adr);

    csr_write(CTRL, make_ctrl(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, algo, 3'd0, 1'b0));

    repeat (abort_after_cycles) @(posedge clk);
    $display("  Issuing STOP after %0d cycles...", abort_after_cycles);
    csr_write(CTRL, make_ctrl(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, algo, 3'd0, 1'b0));

    wait_done();
    report_mbist(name);
  endtask

  // Helper: run MBIST with injected fault (to demonstrate stop-on-fail)
  task automatic run_with_fault(
      input string name,
      input logic stop_on_fail,
      input int unsigned inject_after_cycles
  );
    time t0, t1;

    banner({"TEST: ", name});
    do_reset();

    csr_write(STARTADR, 32'h0);
    csr_write(ENDADR,   32'hFC);

    t0 = $time;
    csr_write(CTRL, make_ctrl(1'b1, 1'b1, 1'b0, 1'b0, stop_on_fail, 2'd0, 3'd0, 1'b0)); // algo=0 MATS+

    repeat (inject_after_cycles) @(posedge clk);
    portA_write_byte(8'h10, 8'hAA);
    $display("  Injected fault: byte @0x10 = 0xAA (after %0d cycles)", inject_after_cycles);

    wait_done();
    t1 = $time;

    report_mbist(name);
    $display("[%s] Duration: %0t ns", name, (t1 - t0));
  endtask

  // ------------------------------------------------------------
  // Main program
  // ------------------------------------------------------------

  initial begin
    $display("=== TB: MBIST as CSR Peripheral (ENHANCED) ===");
    do_reset();

    // --------------------------------------------------------
    banner("SMOKE: Normal CPU-port sanity (no takeover)");
    $display("Normal write/read sanity...");
    normal_write_word(8'h20, 32'hDEAD_BEEF);
    normal_read_word (8'h20, rd);
    $display("Read back: 0x%08x", rd);

    // --------------------------------------------------------
    banner("NEGATIVE: START without TEST_MODE should NOT start");
    csr_write(STARTADR, 32'h0);
    csr_write(ENDADR,   32'hFC);
    csr_write(CTRL, make_ctrl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'd0, 3'd0, 1'b0));
    repeat (10) @(posedge clk);
    csr_read(STATUS, st);
    $display("Expected: busy=0, done=0. Observed: busy=%0d done=%0d", st[ST_BUSY], st[ST_DONE]);

    // --------------------------------------------------------
    // Algorithms coverage
    // --------------------------------------------------------
    do_reset();
    run_mbist("MATS+ (algo=0) PASS", 32'h0, 32'hFC, 2'd0,
             1'b0, 3'd0, 1'b0, 1'b0, 16'h0000);

    do_reset();
    run_mbist("MATS++ (algo=1) PASS", 32'h0, 32'hFC, 2'd1,
             1'b0, 3'd0, 1'b0, 1'b0, 16'h0000);

    do_reset();
    run_mbist("March C- (algo=2) PASS", 32'h0, 32'hFC, 2'd2,
             1'b0, 3'd0, 1'b0, 1'b0, 16'h0000);

    // --------------------------------------------------------
    // Background feature
    // --------------------------------------------------------
    do_reset();
    run_mbist("MATS+ with BG_ENABLE=1, BG_COUNT=0 (auto=2)", 32'h0, 32'hFC, 2'd0,
             1'b1, 3'd0, 1'b0, 1'b0, 16'h0000);

    do_reset();
    run_mbist("MATS+ with BG_ENABLE=1, BG_COUNT=3", 32'h0, 32'hFC, 2'd0,
             1'b1, 3'd3, 1'b0, 1'b0, 16'h0000);

    // --------------------------------------------------------
    // Signature check (pass + fail)
    // --------------------------------------------------------
    do_reset();
    banner("CAPTURE baseline signature for MATS+");
    csr_write(STARTADR, 32'h0);
    csr_write(ENDADR,   32'hFC);
    csr_write(CTRL, make_ctrl(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'd0, 3'd0, 1'b0));
    wait_done();
    csr_read(SIG, sig);
    $display("Baseline SIG (MATS+): 0x%04x", sig[15:0]);

    do_reset();
    run_mbist("SIG_CHECK enabled with correct EXPSIG", 32'h0, 32'hFC, 2'd0,
             1'b0, 3'd0, 1'b0, 1'b1, sig[15:0]);

    do_reset();
    run_mbist("SIG_CHECK enabled with WRONG EXPSIG (expect mismatch+fail)", 32'h0, 32'hFC, 2'd0,
             1'b0, 3'd0, 1'b0, 1'b1, (sig[15:0] ^ 16'h0001));

    // --------------------------------------------------------
    // Stop-on-fail (compare durations)
    // --------------------------------------------------------
    run_with_fault("FAULT injected, STOP_ON_FAIL=0 (should finish full algo)", 1'b0, 70);
    run_with_fault("FAULT injected, STOP_ON_FAIL=1 (should stop early)",      1'b1, 70);

    // --------------------------------------------------------
    // Abort via STOP bit
    // --------------------------------------------------------
    do_reset();
    run_and_abort("ABORT example (STOP bit)", 32'h0, 32'h3FC, 2'd2, 40);

    $display("\n=== ALL TESTS DONE ===");
    $finish;
  end

endmodule

