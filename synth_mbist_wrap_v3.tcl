# ==============================
# # Design Compiler script - MBIST wrapper (CSR + core)
# # Top: mbist_csr_wrap
# # Synthesizes MBIST IP logic; RAM remains external (ram_* ports)
# # ==============================
set TOP mbist_csr_wrap

file mkdir dc_work
file mkdir dc_out

define_design_lib work -path ./dc_work

# Put RTL + pdt2002.db in the same directory, or extend search_path.
 set search_path [list . [pwd]]

 # Libraries
 # NOTE: "*" keeps DC's default libraries in the link path.
 set_app_var target_library [list pdt2002.db]
 set_app_var link_library   [list * pdt2002.db]

 # Extra setup (dont_use cells, etc.)
 source ./pdt2002.dc_setup.tcl

 # RTL list (wrapper instantiates mbist_core)
 set RTL [list \
   mbist_core_v3.sv \
     mbist_csr_wrap_v3.sv \
     ]

     analyze   -library work -format sverilog $RTL
     elaborate $TOP
     current_design $TOP
     link

     check_design
     check_timing

     # ------------------------------
     # Constraints
     # ------------------------------
     create_clock -name clk -period 27 [get_ports clk]
     set_dont_touch_network [get_ports clk]
     set_clock_uncertainty 0.2 [get_clocks clk]

     # Treat async reset as non-timed
     if {[sizeof_collection [get_ports rst_n]] > 0} {
       set_false_path -from [get_ports rst_n]
       }

       # I/O delays (0ns default, but explicit)
       set_input_delay  0.0 -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
       set_output_delay 0.0 -clock clk [all_outputs]

       # ------------------------------
       # Compile
       # ------------------------------
       compile_ultra

       # ------------------------------
       # Reports
       # ------------------------------
       redirect -file dc_out/report_design_${TOP}.rpt { report_design }
       redirect -file dc_out/report_qor_${TOP}.rpt    { report_qor }
       redirect -file dc_out/report_area_${TOP}.rpt   { report_area -hierarchy -nosplit }
       redirect -file dc_out/report_timing_${TOP}.rpt { report_timing -max_paths 20 -delay_type max -nosplit }
       redirect -file dc_out/report_power_${TOP}.rpt  { report_power -nosplit }

       # ------------------------------
       # Outputs
       # ------------------------------
       write -hierarchy -format verilog -output dc_out/${TOP}_synth.v
       write -hierarchy -format ddc     -output dc_out/${TOP}.ddc
       write_sdc dc_out/${TOP}.sdc

       quit
