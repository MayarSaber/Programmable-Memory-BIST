#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# run_vsim.sh
# - Compiles with vlog, suppresses noisy SVCHK warnings from older Questa
# - Runs vsim in batch mode with bounded execution (via +maxcycles in tb)
# -----------------------------------------------------------------------------

# You can override these when calling the script, e.g.:
#   ./run_vsim.sh firmware/firmware.hex 500000 000000FC 0 1
FIRMWARE="${1:-firmware/firmware.hex}"
MAXCYCLES="${2:-500000}"
MBIST_END="${3:-000000FC}"
MBIST_ALGO="${4:-0}"
VERBOSE="${5:-1}"

# Clean work library
rm -rf work
vlib work

# Compile
# -suppress 2583: Questa 10.5 (2016) "SVCHK always_comb/always_latch conflict checking not supported" spam
# (keep other suppressions you already used if needed)
vlog -sv -work work \
  -suppress 2583 \
  "+incdir+../../rtl/include" \
  "+incdir+../tb_riscv/include" \
  -f files.f

# Run
# -suppress 8315: "No condition is true in the unique/priority if/case" (often at time 0 due to Xs)
# Add +maxcycles so tb can stop itself; then quit cleanly.
VSIM_ARGS=(
  -c
  -suppress 8315
  work.tb_top
  "+firmware=${FIRMWARE}"
  "+maxcycles=${MAXCYCLES}"
)

# Optional MBIST arguments (tb must support them)
VSIM_ARGS+=(
  "+mbist_end=${MBIST_END}"
  "+mbist_algo=${MBIST_ALGO}"
)

if [[ "${STOP_AFTER_MBIST:-0}" != "0" ]]; then
  VSIM_ARGS+=("+stop_after_mbist")
fi

# Optional verbose flag (tb must support it)
if [[ "${VERBOSE}" != "0" ]]; then
  VSIM_ARGS+=("+verbose")
fi

vsim "${VSIM_ARGS[@]}" -do "run -all; quit -f"

