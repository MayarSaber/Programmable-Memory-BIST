module mbist_system_top #(
  parameter int unsigned ADDR_WIDTH = 8,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned MISR_WIDTH = 16,
  parameter int unsigned INSTR_RDATA_WIDTH = 128
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Simple CSR interface
  input  logic                   csr_we,
  input  logic                   csr_re,
  input  logic [7:0]             csr_addr,
  input  logic [31:0]            csr_wdata,
  output logic [31:0]            csr_rdata,

  // Normal operation Port B side (e.g., CPU / bus)
  input  logic                   n_en_b,
  input  logic                   n_we_b,
  input  logic [ADDR_WIDTH-1:0]  n_addr_b,
  input  logic [DATA_WIDTH-1:0]  n_wdata_b,
  input  logic [3:0]             n_be_b,
  output logic [DATA_WIDTH-1:0]  n_rdata_b
);

  // Wires between wrapper and RAM port B
  logic                   ram_en_b;
  logic                   ram_we_b;
  logic [ADDR_WIDTH-1:0]  ram_addr_b;
  logic [DATA_WIDTH-1:0]  ram_wdata_b;
  logic [3:0]             ram_be_b;
  logic [DATA_WIDTH-1:0]  ram_rdata_b;

  // Tie-off RAM Port A (unused in synthesis top)
  logic                   en_a, we_a;
  logic [ADDR_WIDTH-1:0]  addr_a;
  logic [DATA_WIDTH-1:0]  wdata_a;
  logic [INSTR_RDATA_WIDTH-1:0] rdata_a;
  logic [3:0]             be_a;

  assign en_a   = 1'b0;
  assign we_a   = 1'b0;
  assign addr_a = '0;
  assign wdata_a= '0;
  assign be_a   = 4'b0000;

  // Memory
  dp_ram #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .INSTR_RDATA_WIDTH(INSTR_RDATA_WIDTH)
  ) u_ram (
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

  // Wrapper (includes MBIST core)
  mbist_csr_wrap #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MISR_WIDTH(MISR_WIDTH)
  ) u_wrap (
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

endmodule
