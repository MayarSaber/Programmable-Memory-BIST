module mbist_csr_wrap #(
  parameter int unsigned ADDR_WIDTH = 8,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned MISR_WIDTH = 16
)(
  input  logic                   clk,
  input  logic                   rst_n,

  // -----------------------------
  // Simple CSR interface
  // -----------------------------
  input  logic                   csr_we,
  input  logic                   csr_re,
  input  logic [7:0]             csr_addr,   // byte address
  input  logic [31:0]            csr_wdata,
  output logic [31:0]            csr_rdata,

  // -----------------------------
  // "Normal operation" Port B side (e.g., CPU / bus)
  // -----------------------------
  input  logic                   n_en_b,
  input  logic                   n_we_b,
  input  logic [ADDR_WIDTH-1:0]  n_addr_b,
  input  logic [DATA_WIDTH-1:0]  n_wdata_b,
  input  logic [3:0]             n_be_b,
  output logic [DATA_WIDTH-1:0]  n_rdata_b,

  // -----------------------------
  // Physical RAM Port B (to dp_ram)
  // -----------------------------
  output logic                   ram_en_b,
  output logic                   ram_we_b,
  output logic [ADDR_WIDTH-1:0]  ram_addr_b,
  output logic [DATA_WIDTH-1:0]  ram_wdata_b,
  output logic [3:0]             ram_be_b,
  input  logic [DATA_WIDTH-1:0]  ram_rdata_b
);

  // CSR map (byte offsets)
  localparam logic [7:0] CSR_CTRL     = 8'h00;
  localparam logic [7:0] CSR_STARTADR = 8'h04;
  localparam logic [7:0] CSR_ENDADR   = 8'h08;
  localparam logic [7:0] CSR_STATUS   = 8'h0C;
  localparam logic [7:0] CSR_SIG      = 8'h10;
  localparam logic [7:0] CSR_ERRADR   = 8'h14;
  localparam logic [7:0] CSR_ERREXP   = 8'h18;
  localparam logic [7:0] CSR_ERRGOT   = 8'h1C;
  localparam logic [7:0] CSR_EXPSIG   = 8'h20; // expected signature (optional)

  // CTRL fields
  // [0]  TEST_MODE (1: MBIST can take RAM)
  // [1]  START     (write 1 => start)
  // [2]  STOP      (write 1 => abort)
  // [3]  BG_ENABLE
  // [4]  STOP_ON_FAIL
  // [6:5] ALGO_SEL   0=MATS+ 1=MATS++ 2=March C-
  // [9:7] BG_COUNT   (0 => auto)
  // [10] SIG_CHECK_EN (if 1: require signature == EXPSIG to PASS)

  logic        test_mode_reg;
  logic        bg_enable_reg;
  logic [2:0]  bg_count_reg;
  logic        stop_on_fail_reg;
  logic [1:0]  algo_sel_reg;
  logic        sig_check_en_reg;
  logic [MISR_WIDTH-1:0] exp_sig_reg;

  logic [ADDR_WIDTH-1:0] start_addr_reg;
  logic [ADDR_WIDTH-1:0] end_addr_reg;

  // Run control
  logic run_active;
  logic start_pend;

  // Latched results
  logic done_lat, pass_lat, fail_lat, aborted_lat;
  logic [MISR_WIDTH-1:0] sig_lat;
  logic err_valid_lat;
  logic [ADDR_WIDTH-1:0] err_addr_lat;
  logic [DATA_WIDTH-1:0] err_exp_lat, err_got_lat;
  logic sig_mismatch_lat;

  // Core signals
  logic                   c_en_b, c_we_b;
  logic [ADDR_WIDTH-1:0]  c_addr_b;
  logic [DATA_WIDTH-1:0]  c_wdata_b;
  logic [3:0]             c_be_b;

  logic c_busy, c_done, c_pass, c_fail;
  logic [MISR_WIDTH-1:0] c_signature;
  logic c_err_valid;
  logic [ADDR_WIDTH-1:0] c_err_addr;
  logic [DATA_WIDTH-1:0] c_err_expected, c_err_got;

  // Pulses from CSR writes (synchronous)
  logic start_fire, stop_fire;

  // Track DONE rising edge to avoid false completion when restarting
  logic c_done_q;
  logic c_done_rise;

  // Signature mismatch (checked when capturing DONE)
  logic mismatch_now;

  // Start pulse to core (1-cycle)
  // IMPORTANT: must be combinational from start_pend so mbist_core sees it at the
  // *same* clock edge. If we generate it with a registered nonblocking assignment,
  // mbist_core will see the previous value and miss the pulse.
  logic core_start_pulse;

  // Core reset strategy: tie reset_n to global rst_n (no reset gating).
  // The core itself supports re-run from DONE on a new START.
  logic core_rst_n;

  assign start_fire = csr_we && (csr_addr == CSR_CTRL) && csr_wdata[1];
  assign stop_fire  = csr_we && (csr_addr == CSR_CTRL) && csr_wdata[2];

  // Keep the core reset tied to the global reset. This avoids
  // async reset-gating with run_active (which can cause missed START).
  assign core_rst_n = rst_n;
  // Combinational 1-cycle start pulse derived from start_pend.
  // start_pend is set on CSR START, then cleared on the next clock edge.
  assign core_start_pulse = start_pend;

  assign c_done_rise = c_done && !c_done_q;
  assign mismatch_now = sig_check_en_reg && (c_signature != exp_sig_reg);

  // -----------------------------
  // CSR write logic + run control
  // -----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      test_mode_reg    <= 1'b0;
      bg_enable_reg    <= 1'b0;
      bg_count_reg     <= 3'd0;
      stop_on_fail_reg <= 1'b0;
      algo_sel_reg     <= 2'd0;
      sig_check_en_reg <= 1'b0;
      exp_sig_reg      <= '0;

      c_done_q         <= 1'b0;

      start_addr_reg   <= '0;
      end_addr_reg     <= ({ADDR_WIDTH{1'b1}} - 3);

      run_active       <= 1'b0;
      start_pend       <= 1'b0;

      done_lat         <= 1'b0;
      pass_lat         <= 1'b0;
      fail_lat         <= 1'b0;
      aborted_lat      <= 1'b0;
      sig_lat          <= '0;
      sig_mismatch_lat <= 1'b0;

      err_valid_lat    <= 1'b0;
      err_addr_lat     <= '0;
      err_exp_lat      <= '0;
      err_got_lat      <= '0;

    end else begin
      // CSR writes

      // Sample core DONE level for edge detection
      c_done_q <= c_done;
      if (csr_we) begin
        unique case (csr_addr)
          CSR_CTRL: begin
            test_mode_reg    <= csr_wdata[0];
            bg_enable_reg    <= csr_wdata[3];
            stop_on_fail_reg <= csr_wdata[4];
            algo_sel_reg     <= csr_wdata[6:5];
            bg_count_reg     <= csr_wdata[9:7];
            sig_check_en_reg <= csr_wdata[10];
          end
          CSR_STARTADR: start_addr_reg <= csr_wdata[ADDR_WIDTH-1:0];
          CSR_ENDADR:   end_addr_reg   <= csr_wdata[ADDR_WIDTH-1:0];
          CSR_EXPSIG:   exp_sig_reg    <= csr_wdata[MISR_WIDTH-1:0];
          default: begin end
        endcase
      end

      // START
      // Accept START only when not already running AND test_mode=1.
      // Also accept it if TEST_MODE is being set in the same CSR write.
      if (start_fire && !run_active && (test_mode_reg || csr_wdata[0])) begin
        done_lat         <= 1'b0;
        pass_lat         <= 1'b0;
        fail_lat         <= 1'b0;
        aborted_lat      <= 1'b0;
        sig_lat          <= '0;
        sig_mismatch_lat <= 1'b0;

        err_valid_lat    <= 1'b0;
        err_addr_lat     <= '0;
        err_exp_lat      <= '0;
        err_got_lat      <= '0;

        run_active       <= 1'b1;
        start_pend       <= 1'b1; // will become a 1-cycle pulse at the *next* clk edge
      end

      // Consume pending start (this is the actual 1-cycle pulse seen by mbist_core)
      if (start_pend) begin
        start_pend <= 1'b0;
      end

      // STOP
      if (stop_fire && run_active) begin
        aborted_lat      <= 1'b1;
        done_lat         <= 1'b1;
        pass_lat         <= 1'b0;
        fail_lat         <= 1'b0;
        sig_lat          <= sig_lat; // keep whatever we latched (usually 0)
        sig_mismatch_lat <= 1'b0;

        run_active       <= 1'b0;   // abort: release RAM back to normal port
        start_pend       <= 1'b0;
      end

      // Capture when core completes
      if (run_active && c_done_rise) begin
        done_lat         <= 1'b1;
        pass_lat         <= c_pass && !mismatch_now;
        fail_lat         <= c_fail || mismatch_now;
        sig_lat          <= c_signature;
        sig_mismatch_lat <= mismatch_now;

        err_valid_lat    <= c_err_valid;
        err_addr_lat     <= c_err_addr;
        err_exp_lat      <= c_err_expected;
        err_got_lat      <= c_err_got;

        run_active       <= 1'b0;   // release RAM back to normal port
        start_pend       <= 1'b0;
      end

    end
  end

  // -----------------------------
  // Instantiate mbist_core
  // -----------------------------
  mbist_core #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MISR_WIDTH(MISR_WIDTH)
  ) u_core (
    .clk(clk),
    .rst_n(core_rst_n),

    .start(core_start_pulse),
    .algo_sel(algo_sel_reg),
    .bg_enable(bg_enable_reg),
    .bg_count(bg_count_reg),
    .stop_on_fail(stop_on_fail_reg),
    .start_addr_cfg(start_addr_reg),
    .end_addr_cfg(end_addr_reg),

    .en_b(c_en_b),
    .we_b(c_we_b),
    .addr_b(c_addr_b),
    .wdata_b(c_wdata_b),
    .be_b(c_be_b),
    .rdata_b(ram_rdata_b),

    .busy(c_busy),
    .done(c_done),
    .pass(c_pass),
    .fail(c_fail),

    .signature(c_signature),

    .err_valid(c_err_valid),
    .err_addr(c_err_addr),
    .err_expected(c_err_expected),
    .err_got(c_err_got)
  );

  // -----------------------------
  // RAM takeover mux
  // -----------------------------
  logic mbist_takeover;
  assign mbist_takeover = test_mode_reg && run_active;

  always_comb begin
    if (mbist_takeover) begin
      ram_en_b    = c_en_b;
      ram_we_b    = c_we_b;
      ram_addr_b  = c_addr_b;
      ram_wdata_b = c_wdata_b;
      ram_be_b    = c_be_b;
      n_rdata_b   = '0;       // CPU shouldn't use RAM during MBIST
    end else begin
      ram_en_b    = n_en_b;
      ram_we_b    = n_we_b;
      ram_addr_b  = n_addr_b;
      ram_wdata_b = n_wdata_b;
      ram_be_b    = n_be_b;
      n_rdata_b   = ram_rdata_b;
    end
  end

  // -----------------------------
  // CSR readback
  // -----------------------------
  always_comb begin
    csr_rdata = 32'h0;
    if (csr_re) begin
      unique case (csr_addr)
        CSR_CTRL: begin
          csr_rdata[0]    = test_mode_reg;
          csr_rdata[3]    = bg_enable_reg;
          csr_rdata[4]    = stop_on_fail_reg;
          csr_rdata[6:5]  = algo_sel_reg;
          csr_rdata[9:7]  = bg_count_reg;
          csr_rdata[10]   = sig_check_en_reg;
        end
        CSR_STARTADR: csr_rdata[ADDR_WIDTH-1:0] = start_addr_reg;
        CSR_ENDADR:   csr_rdata[ADDR_WIDTH-1:0] = end_addr_reg;
        CSR_STATUS: begin
          csr_rdata[0] = run_active;        // busy
          csr_rdata[1] = done_lat;
          csr_rdata[2] = pass_lat;
          csr_rdata[3] = fail_lat;
          csr_rdata[4] = aborted_lat;
          csr_rdata[5] = err_valid_lat;
          csr_rdata[6] = sig_mismatch_lat;
          csr_rdata[7] = mbist_takeover;
        end
        CSR_SIG:      csr_rdata[MISR_WIDTH-1:0] = sig_lat;
        CSR_EXPSIG:   csr_rdata[MISR_WIDTH-1:0] = exp_sig_reg;
        CSR_ERRADR:   csr_rdata[ADDR_WIDTH-1:0] = err_addr_lat;
        CSR_ERREXP:   csr_rdata = err_exp_lat;
        CSR_ERRGOT:   csr_rdata = err_got_lat;
        default: csr_rdata = 32'h0;
      endcase
    end
  end

endmodule

