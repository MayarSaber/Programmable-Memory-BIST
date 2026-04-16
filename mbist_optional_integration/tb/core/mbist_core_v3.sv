module mbist_core #(
  parameter int unsigned ADDR_WIDTH = 8,
  parameter int unsigned DATA_WIDTH = 32,

  // dp_ram is byte-addressed, and aligns internally to 32-bit boundary.
  // So "word addresses" are byte addresses stepping by +4.
  parameter logic [ADDR_WIDTH-1:0] START_ADDR_DFLT = '0,
  parameter logic [ADDR_WIDTH-1:0] END_ADDR_DFLT   = ({ADDR_WIDTH{1'b1}} - 3), // = 2^ADDR_WIDTH - 4

  parameter int unsigned MISR_WIDTH = 16,
  // CRC-CCITT: x^16 + x^12 + x^5 + 1  -> 0x1021
  parameter logic [MISR_WIDTH-1:0] MISR_POLY = 16'h1021
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // "Register-like" configuration inputs (can be driven by real CSRs later)
  input  logic                     start,
  input  logic [1:0]               algo_sel,       // 0=MATS+, 1=MATS++, 2=March C-, others reserved
  input  logic                     bg_enable,      // 1 = run multiple backgrounds
  input  logic [2:0]               bg_count,       // number of backgrounds (0 => auto for DATA_WIDTH)
  input  logic                     stop_on_fail,   // optional: stop early when first fail occurs
  input  logic [ADDR_WIDTH-1:0]    start_addr_cfg, // byte address
  input  logic [ADDR_WIDTH-1:0]    end_addr_cfg,   // byte address

  // Memory Port B interface (to dp_ram)
  output logic                     en_b,
  output logic                     we_b,
  output logic [ADDR_WIDTH-1:0]    addr_b,
  output logic [DATA_WIDTH-1:0]    wdata_b,
  output logic [3:0]               be_b,
  input  logic [DATA_WIDTH-1:0]    rdata_b,

  // Result / debug
  output logic                     busy,
  output logic                     done,
  output logic                     pass,
  output logic                     fail,

  output logic [MISR_WIDTH-1:0]    signature,

  output logic                     err_valid,
  output logic [ADDR_WIDTH-1:0]    err_addr,
  output logic [DATA_WIDTH-1:0]    err_expected,
  output logic [DATA_WIDTH-1:0]    err_got
);

  // ----------------------------
  // Types / constants
  // ----------------------------
  // +4 bytes per word (dp_ram word-aligned to 32-bit). IMPORTANT: STEP must be ADDR_WIDTH-wide.
  // The previous cast "logic'(4)" truncates to 1-bit and becomes 0, which stalls address walk forever.
  localparam logic [ADDR_WIDTH-1:0] STEP = 'd4;

  typedef enum logic [1:0] { DIR_ANY, DIR_UP, DIR_DOWN } dir_t;
  typedef enum logic [1:0] { OP_W0, OP_W1, OP_R0, OP_R1 } op_t;
  typedef enum logic [1:0] { ST_IDLE, ST_EXEC, ST_READ_SAMPLE, ST_DONE } st_t;

  st_t state;

  // sequencer state
  logic [2:0] elem_idx;   // enough for March C- (6 elems)
  logic [2:0] op_idx;     // enough for max ops in an element
  logic [ADDR_WIDTH-1:0] cur_addr;

  logic [2:0] bg_idx;
  logic [2:0] bg_total;

  logic fail_latched;

  // read pipeline
  logic read_pending;
  logic [DATA_WIDTH-1:0] expected_q;

  // resolved addresses (use cfg, otherwise defaults)
  logic [ADDR_WIDTH-1:0] start_addr;
  logic [ADDR_WIDTH-1:0] end_addr;

  // ----------------------------
  // Helpers: algorithm decode
  // ----------------------------
  function automatic int unsigned num_elems(input logic [1:0] a);
    case (a)
      2'd0: num_elems = 3; // MATS+
      2'd1: num_elems = 3; // MATS++
      2'd2: num_elems = 6; // March C-
      default: num_elems = 3;
    endcase
  endfunction

  function automatic dir_t elem_dir(input logic [1:0] a, input logic [2:0] e);
    case (a)
      2'd0, 2'd1: begin // MATS+/MATS++
        case (e)
          0: elem_dir = DIR_ANY;
          1: elem_dir = DIR_UP;
          2: elem_dir = DIR_DOWN;
          default: elem_dir = DIR_ANY;
        endcase
      end
      2'd2: begin // March C-
        case (e)
          0: elem_dir = DIR_ANY;   // (w0)
          1: elem_dir = DIR_UP;    // ↑ (r0, w1)
          2: elem_dir = DIR_UP;    // ↑ (r1, w0)
          3: elem_dir = DIR_DOWN;  // ↓ (r0, w1)
          4: elem_dir = DIR_DOWN;  // ↓ (r1, w0)
          5: elem_dir = DIR_ANY;   // (r0)
          default: elem_dir = DIR_ANY;
        endcase
      end
      default: elem_dir = DIR_ANY;
    endcase
  endfunction

  function automatic int unsigned elem_op_count(input logic [1:0] a, input logic [2:0] e);
    case (a)
      2'd0: begin // MATS+ : (w0), ↑(r0,w1), ↓(r1,w0)
        case (e)
          0: elem_op_count = 1;
          1: elem_op_count = 2;
          2: elem_op_count = 2;
          default: elem_op_count = 1;
        endcase
      end
      2'd1: begin // MATS++ : (w0), ↑(r0,w1), ↓(r1,w0,r0)
        case (e)
          0: elem_op_count = 1;
          1: elem_op_count = 2;
          2: elem_op_count = 3;
          default: elem_op_count = 1;
        endcase
      end
      2'd2: begin // March C-
        case (e)
          0: elem_op_count = 1;
          1: elem_op_count = 2;
          2: elem_op_count = 2;
          3: elem_op_count = 2;
          4: elem_op_count = 2;
          5: elem_op_count = 1;
          default: elem_op_count = 1;
        endcase
      end
      default: elem_op_count = 1;
    endcase
  endfunction

  function automatic op_t elem_op(input logic [1:0] a, input logic [2:0] e, input logic [2:0] oi);
    case (a)
      2'd0: begin // MATS+
        case (e)
          0: elem_op = OP_W0;
          1: elem_op = (oi==0) ? OP_R0 : OP_W1;
          2: elem_op = (oi==0) ? OP_R1 : OP_W0;
          default: elem_op = OP_W0;
        endcase
      end
      2'd1: begin // MATS++
        case (e)
          0: elem_op = OP_W0;
          1: elem_op = (oi==0) ? OP_R0 : OP_W1;
          2: begin
            case (oi)
              0: elem_op = OP_R1;
              1: elem_op = OP_W0;
              2: elem_op = OP_R0;
              default: elem_op = OP_R0;
            endcase
          end
          default: elem_op = OP_W0;
        endcase
      end
      2'd2: begin // March C-
        case (e)
          0: elem_op = OP_W0;
          1: elem_op = (oi==0) ? OP_R0 : OP_W1;
          2: elem_op = (oi==0) ? OP_R1 : OP_W0;
          3: elem_op = (oi==0) ? OP_R0 : OP_W1;
          4: elem_op = (oi==0) ? OP_R1 : OP_W0;
          5: elem_op = OP_R0;
          default: elem_op = OP_W0;
        endcase
      end
      default: elem_op = OP_W0;
    endcase
  endfunction

  // ----------------------------
  // Helpers: data background (w1 pattern, w0 = ~w1)
  // ----------------------------
  function automatic int unsigned auto_bg_total();
    // slides: ceil(log2(m)) + 1
    auto_bg_total = $clog2(DATA_WIDTH) + 1;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] bg_w1(input logic [2:0] idx);
    // idx=0 -> all 1s
    // idx=1 -> half ones half zeros
    // ...
    // idx=log2(m) -> alternating 1010...
    logic [DATA_WIDTH-1:0] p;
    int unsigned seg_len;
    int unsigned cnt;
    logic bit_val;

    p = '0;

    seg_len = (DATA_WIDTH >> idx);
    if (seg_len == 0) seg_len = 1;

    bit_val = 1'b1;
    cnt = 0;

    for (int unsigned i = 0; i < DATA_WIDTH; i++) begin
      p[i] = bit_val;
      cnt++;
      if (cnt == seg_len) begin
        cnt = 0;
        bit_val = ~bit_val;
      end
    end

    return p;
  endfunction

  logic [DATA_WIDTH-1:0] W1, W0;

  // ----------------------------
  // Helpers: MISR update (bit-serial fold)
  // ----------------------------
  function automatic logic [MISR_WIDTH-1:0] misr_fold(
    input logic [MISR_WIDTH-1:0] s,
    input logic [DATA_WIDTH-1:0] din
  );
    logic [MISR_WIDTH-1:0] t;
    t = s;

    // fold DATA_WIDTH bits (order not critical as long as consistent)
    for (int unsigned k = 0; k < DATA_WIDTH; k++) begin
      logic fb;
      fb = t[MISR_WIDTH-1] ^ din[DATA_WIDTH-1-k];
      t  = {t[MISR_WIDTH-2:0], 1'b0};
      if (fb) t ^= MISR_POLY;
      t[0] = fb;
    end

    return t;
  endfunction

  // ----------------------------
  // Derived config
  // ----------------------------
  always_comb begin
    // align start/end to 32-bit boundary to match dp_ram behavior
    start_addr = {start_addr_cfg[ADDR_WIDTH-1:2], 2'b00};
    end_addr   = {end_addr_cfg[ADDR_WIDTH-1:2], 2'b00};

    if ((start_addr_cfg === '0) && (end_addr_cfg === '0)) begin
      start_addr = START_ADDR_DFLT;
      end_addr   = END_ADDR_DFLT;
    end

    bg_total = (bg_count != 0) ? bg_count : logic'(auto_bg_total());

    W1 = bg_w1(bg_idx);
    W0 = ~W1;
  end

  // ----------------------------
  // Outputs to memory
  // ----------------------------
  always_comb begin
    en_b    = 1'b0;
    we_b    = 1'b0;
    addr_b  = cur_addr;
    wdata_b = '0;
    be_b    = 4'b1111;

    busy = (state != ST_IDLE) && (state != ST_DONE);
    done = (state == ST_DONE);
    fail = fail_latched;
    pass = done && !fail_latched;

    if (state == ST_EXEC) begin
      op_t op_now;
      op_now = elem_op(algo_sel, elem_idx, op_idx);
      unique case (op_now)
        OP_W0: begin en_b = 1'b1; we_b = 1'b1; wdata_b = W0; end
        OP_W1: begin en_b = 1'b1; we_b = 1'b1; wdata_b = W1; end
        OP_R0: begin en_b = 1'b1; we_b = 1'b0; end
        OP_R1: begin en_b = 1'b1; we_b = 1'b0; end
        default: begin end
      endcase
    end
  end

  // ----------------------------
  // Signature mixing helper
  // (includes address and op type to better reflect "bus operations")
  // ----------------------------
  function automatic logic [DATA_WIDTH-1:0] sig_mix(
    input logic [DATA_WIDTH-1:0] data_in,
    input logic                  is_write,
    input logic [ADDR_WIDTH-1:0] addr_in
  );
    logic [DATA_WIDTH-1:0] x;
    x = data_in;

    // XOR in address (LSBs) and op type (MSB) so writes/reads at different
    // addresses contribute differently to the signature.
    x[ADDR_WIDTH-1:0] ^= addr_in;
    x[DATA_WIDTH-1]   ^= is_write;

    return x;
  endfunction

  // ----------------------------
  // Main FSM
  // ----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      cur_addr     <= START_ADDR_DFLT;
      elem_idx     <= '0;
      op_idx       <= '0;
      bg_idx       <= '0;
      fail_latched <= 1'b0;

      read_pending <= 1'b0;
      expected_q   <= '0;

      signature    <= '0;

      err_valid    <= 1'b0;
      err_addr     <= '0;
      err_expected <= '0;
      err_got      <= '0;

    end else begin
      unique case (state)

        ST_IDLE: begin
          fail_latched <= 1'b0;
          err_valid    <= 1'b0;
          signature    <= '0;

          elem_idx     <= '0;
          op_idx       <= '0;
          bg_idx       <= '0;
          read_pending <= 1'b0;

          cur_addr     <= start_addr;

          if (start) begin
            if (elem_dir(algo_sel, 0) == DIR_DOWN)
              cur_addr <= end_addr;
            else
              cur_addr <= start_addr;

            state <= ST_EXEC;
          end
        end

        ST_EXEC: begin
          if (stop_on_fail && fail_latched) begin
            state <= ST_DONE;
          end else begin
            op_t op_now;
            int unsigned op_cnt;

            op_now = elem_op(algo_sel, elem_idx, op_idx);
            op_cnt = elem_op_count(algo_sel, elem_idx);

            // If this is a read, schedule sampling next cycle
            if (op_now == OP_R0 || op_now == OP_R1) begin
              read_pending <= 1'b1;
              expected_q   <= (op_now == OP_R0) ? W0 : W1;
              state        <= ST_READ_SAMPLE;

            end else begin
              // Write operation: update signature on the write data + addr/op
              if (op_now == OP_W0 || op_now == OP_W1) begin
                logic [DATA_WIDTH-1:0] wdat;
                wdat = (op_now == OP_W0) ? W0 : W1;
                signature <= misr_fold(signature, sig_mix(wdat, 1'b1, cur_addr));
              end

              // advance op/address/element
              if (op_idx == (op_cnt-1)) begin
                dir_t d;
                d = elem_dir(algo_sel, elem_idx);
                if (d == DIR_ANY) d = DIR_UP;

                if (d == DIR_UP) begin
                  if (cur_addr == end_addr) begin
                    op_idx   <= '0;
                    elem_idx <= elem_idx + 1;

                    if ((elem_idx + 1) == num_elems(algo_sel)) begin
                      if (bg_enable && (bg_idx + 1 < bg_total)) begin
                        bg_idx   <= bg_idx + 1;
                        elem_idx <= '0;
                      end else begin
                        state <= ST_DONE;
                      end
                    end

                    if (elem_dir(algo_sel, elem_idx + 1) == DIR_DOWN)
                      cur_addr <= end_addr;
                    else
                      cur_addr <= start_addr;

                  end else begin
                    cur_addr <= cur_addr + STEP;
                    op_idx   <= '0;
                  end

                end else begin // DIR_DOWN
                  if (cur_addr == start_addr) begin
                    op_idx   <= '0;
                    elem_idx <= elem_idx + 1;

                    if ((elem_idx + 1) == num_elems(algo_sel)) begin
                      if (bg_enable && (bg_idx + 1 < bg_total)) begin
                        bg_idx   <= bg_idx + 1;
                        elem_idx <= '0;
                      end else begin
                        state <= ST_DONE;
                      end
                    end

                    if (elem_dir(algo_sel, elem_idx + 1) == DIR_DOWN)
                      cur_addr <= end_addr;
                    else
                      cur_addr <= start_addr;

                  end else begin
                    cur_addr <= cur_addr - STEP;
                    op_idx   <= '0;
                  end
                end

              end else begin
                op_idx <= op_idx + 1;
              end
            end
          end
        end

        ST_READ_SAMPLE: begin
          // dp_ram Port B is synchronous (registered) read.
          // We must wait one full cycle after issuing the read in ST_EXEC
          // before rdata_b is valid for comparison.

          if (read_pending) begin
            // First cycle in ST_READ_SAMPLE: wait for RAM to update rdata_b.
            read_pending <= 1'b0;
            state        <= ST_READ_SAMPLE;
          end else begin
            // Second cycle: rdata_b is now valid -> update signature and compare.
            signature <= misr_fold(signature, sig_mix(rdata_b, 1'b0, cur_addr));

            if (rdata_b !== expected_q) begin
              fail_latched <= 1'b1;
              err_valid    <= 1'b1;
              err_addr     <= cur_addr;
              err_expected <= expected_q;
              err_got      <= rdata_b;
            end

            // Default: return to execute next op
            state <= ST_EXEC;

            // Advance op/address/element exactly once per read op completion
            begin
              int unsigned op_cnt;
              op_cnt = elem_op_count(algo_sel, elem_idx);

              if (op_idx == (op_cnt-1)) begin
                dir_t d;
                d = elem_dir(algo_sel, elem_idx);
                if (d == DIR_ANY) d = DIR_UP;

                if (d == DIR_UP) begin
                  if (cur_addr == end_addr) begin
                    op_idx   <= '0;
                    elem_idx <= elem_idx + 1;

                    if ((elem_idx + 1) == num_elems(algo_sel)) begin
                      if (bg_enable && (bg_idx + 1 < bg_total)) begin
                        bg_idx   <= bg_idx + 1;
                        elem_idx <= '0;
                      end else begin
                        state <= ST_DONE;
                      end
                    end

                    if (elem_dir(algo_sel, elem_idx + 1) == DIR_DOWN)
                      cur_addr <= end_addr;
                    else
                      cur_addr <= start_addr;

                  end else begin
                    cur_addr <= cur_addr + STEP;
                    op_idx   <= '0;
                  end

                end else begin // DIR_DOWN
                  if (cur_addr == start_addr) begin
                    op_idx   <= '0;
                    elem_idx <= elem_idx + 1;

                    if ((elem_idx + 1) == num_elems(algo_sel)) begin
                      if (bg_enable && (bg_idx + 1 < bg_total)) begin
                        bg_idx   <= bg_idx + 1;
                        elem_idx <= '0;
                      end else begin
                        state <= ST_DONE;
                      end
                    end

                    if (elem_dir(algo_sel, elem_idx + 1) == DIR_DOWN)
                      cur_addr <= end_addr;
                    else
                      cur_addr <= start_addr;

                  end else begin
                    cur_addr <= cur_addr - STEP;
                    op_idx   <= '0;
                  end
                end

              end else begin
                op_idx <= op_idx + 1;
              end
            end
          end
        end

        ST_DONE: begin
          state <= ST_DONE; // stay until reset
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

