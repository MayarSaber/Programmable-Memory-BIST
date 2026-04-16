module dp_ram
    #(parameter int unsigned ADDR_WIDTH        = 8,
      parameter int unsigned INSTR_RDATA_WIDTH = 128)
    (input  logic                       clk_i,
     
     //PortA signals
     /*
     en_a_i    -> Enable for port A. If 0, port A does nothing that cycle.
     addr_a_i  -> Address for port A (byte address coming in, but later aligned).
     wdata_a_i ->  32-bit write data for port A.
     rdata_a_o -> 128-bit read output for port A.
     we_a_i    -> Write enable for port A.
     be_a_i    -> Byte enables (one bit per byte of the 32-bit word): ex/be_a_i[0] controls byte 0 (bits 7:0) 
     */
     input  logic                       en_a_i,
     input  logic [ADDR_WIDTH-1:0]      addr_a_i,
     input  logic [31:0]                wdata_a_i,
     output logic [INSTR_RDATA_WIDTH-1:0] rdata_a_o,
     input  logic                       we_a_i,
     input  logic [3:0]                 be_a_i,
     
     //PortB signals
     /* 
     en_b_i    -> Enable for port B. If 0, port B does nothing that cycle.
     addr_b_i  -> Address for port B (byte address coming in, but later aligned).
     wdata_b_i -> 32-bit write data for port B.
     rdata_b_o -> 32-bit read output for port B.
     we_b_i    -> Write enable for port B.
     be_b_i    -> Byte enables (one bit per byte of the 32-bit word): ex/be_b_i[0] controls byte 0 (bits 7:0)
     PortB can read or write 32-bit using en_b_i, we_b_i, be_b_i
     */
     input  logic                       en_b_i,
     input  logic [ADDR_WIDTH-1:0]      addr_b_i,
     input  logic [31:0]                wdata_b_i,
     output logic [31:0]                rdata_b_o,
     input  logic                       we_b_i,
     input  logic [3:0]                 be_b_i);

    // Byte-addressable memory
    //To compute the total bytes in memory --> if ADDR_WIDTH=8, BYTES = 256
    localparam int unsigned BYTES = (1 << ADDR_WIDTH);

    //The actual memory array: 256 entries of 8 bits (byte-addressable).
    logic [7:0] mem [0:BYTES-1];
    //Internal aligned addresses (word-aligned), derived from addr_a_i / addr_b_i
    logic [ADDR_WIDTH-1:0] addr_a_int;
    logic [ADDR_WIDTH-1:0] addr_b_int;

    always_comb begin
        // Align to 32-bit boundary
        // Forcing addresses to be 32-bit aligned by clearing the lowest 2 bits.
        // EX/ if addr_b_i = 0x05, it becomes addr_b_int = 0x04.
        //Meaning: both ports operate in word steps of 4 bytes, even though the memory is byte-addressable
        //MBIST should increment addresses by 4 (STEP = 4).
        addr_a_int = {addr_a_i[ADDR_WIDTH-1:2], 2'b00};
        addr_b_int = {addr_b_i[ADDR_WIDTH-1:2], 2'b00};
    end

    always_ff @(posedge clk_i) begin
        // -------------------------
        // Port A (32-bit write, 128-bit read)
        // -------------------------
        // If port A enabled and write-enabled -> It writes up to 4 bytes into mem[] at: addr_a_int + 0..3 (one 32-bit word)
        // The slicing wdata_a_i[8 +: 8] means “8 bits starting at bit 8”
        // If port A enabled, it always performs a 128-bit read (16 bytes): It packs mem[addr_a_int + 0] into bits [7:0] -> mem[addr_a_int + 1] into [15:8] -> up to 16 bytes total.
        if (en_a_i) begin
            if (we_a_i) begin
                if (be_a_i[0]) mem[addr_a_int + 0] <= wdata_a_i[ 0 +: 8];
                if (be_a_i[1]) mem[addr_a_int + 1] <= wdata_a_i[ 8 +: 8];
                if (be_a_i[2]) mem[addr_a_int + 2] <= wdata_a_i[16 +: 8];
                if (be_a_i[3]) mem[addr_a_int + 3] <= wdata_a_i[24 +: 8];
            end

            // 128-bit read (16 bytes)
            for (int i = 0; i < (INSTR_RDATA_WIDTH/8); i++) begin
                rdata_a_o[(i*8) +: 8] <= mem[addr_a_int + i];
            end
        end
        // If we write and read in the same cycle on port A, the read uses the old mem (since both are <= in same always_ff).
        // If en_a_i is 0, port A does not assign rdata_a_o → it holds its previous value.

        // -------------------------
        // Port B (32-bit read/write)
        // -------------------------
        // Write mode -> Same as port A write: updates 4 bytes using be_b_i.
        // Read mode -> Reads 4 bytes and concatenates them into a 32-bit word. 
        if (en_b_i) begin
            if (we_b_i) begin
                if (be_b_i[0]) mem[addr_b_int + 0] <= wdata_b_i[ 0 +: 8];
                if (be_b_i[1]) mem[addr_b_int + 1] <= wdata_b_i[ 8 +: 8];
                if (be_b_i[2]) mem[addr_b_int + 2] <= wdata_b_i[16 +: 8];
                if (be_b_i[3]) mem[addr_b_int + 3] <= wdata_b_i[24 +: 8];
            end
            else begin
                // synopsys translate_off
                // $test$plusargs("verbose") checks if you launched simulator with +verbose
                // $display(...) prints the address and data.
                // synopsys translate_off/on tells Design Compiler to ignore that block
                if ($test$plusargs("verbose"))
                    $display("read  addr=0x%08x: data=0x%08x", addr_b_int,
                             {mem[addr_b_int + 3], mem[addr_b_int + 2],
                              mem[addr_b_int + 1], mem[addr_b_int + 0]});
                // synopsys translate_on

                rdata_b_o <= {mem[addr_b_int + 3], mem[addr_b_int + 2],
                             mem[addr_b_int + 1], mem[addr_b_int + 0]};
            end
        end
    end

    // ------------------------------------------------------------
    // Simulation-only DPI helpers (NOT synthesizable)
    // DC was failing on: export "DPI-C" ...
    // synopsys translate_off
    // These lines make SystemVerilog functions callable from C via DPI.
    // read_byte(...) -> Returns mem[byte_addr] as an int.
    // write_byte(...) -> Writes one byte into memory and returns it back in other.
    export "DPI-C" function read_byte;
    export "DPI-C" task     write_byte;

    function int read_byte(input logic [ADDR_WIDTH-1:0] byte_addr);
        read_byte = mem[byte_addr];
    endfunction

    task write_byte(input integer byte_addr,
                    input logic [7:0] val,
                    output logic [7:0] other);
        mem[byte_addr] = val;
        other          = mem[byte_addr];
    endtask
    // synopsys translate_on
    // ------------------------------------------------------------

endmodule

