# ---- Packages (must come first)
fpnew/src/fpnew_pkg.sv
../../rtl/include/apu_core_package.sv
../../rtl/include/riscv_defines.sv
../../rtl/include/riscv_tracer_defines.sv
../tb_riscv/include/perturbation_defines.sv

# ---- RTL
../../rtl/riscv_if_stage.sv
../../rtl/riscv_hwloop_controller.sv
../../rtl/riscv_tracer.sv
../../rtl/riscv_prefetch_buffer.sv
../../rtl/riscv_hwloop_regs.sv
../../rtl/riscv_int_controller.sv
../../rtl/riscv_cs_registers.sv
../../rtl/riscv_register_file.sv
../../rtl/riscv_load_store_unit.sv
../../rtl/riscv_id_stage.sv
../../rtl/riscv_core.sv
../../rtl/riscv_compressed_decoder.sv
../../rtl/riscv_fetch_fifo.sv
../../rtl/riscv_alu_div.sv
../../rtl/riscv_prefetch_L0_buffer.sv
../../rtl/riscv_decoder.sv
../../rtl/riscv_mult.sv
../../rtl/register_file_test_wrap.sv
../../rtl/riscv_L0_buffer.sv
../../rtl/riscv_ex_stage.sv
../../rtl/riscv_alu_basic.sv
../../rtl/riscv_pmp.sv
../../rtl/riscv_apu_disp.sv
../../rtl/riscv_alu.sv
../../rtl/riscv_controller.sv

# ---- TB helpers used by mm_ram
../tb_riscv/riscv_random_stall.sv
../tb_riscv/riscv_random_interrupt_generator.sv

# ---- Testbench + RAM + MBIST
riscv_wrapper.sv
dp_ram.sv
tb_top.sv
mbist_csr_wrap_v3.sv
mbist_core_v3.sv
cluster_clock_gating.sv
mm_ram.sv
