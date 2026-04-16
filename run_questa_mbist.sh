#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# Where to store the compiled Questa library directory.
# Logical library name will remain "work".
LIBDIR="${LIBDIR:-work}"

echo "[Questa] Project root: $ROOT_DIR"
echo "[Questa] Library dir:   $LIBDIR"

# Clean previous run artifacts (in the current directory)
rm -f transcript vsim.wlf wlf* *.log *.jou 2>/dev/null || true

# Clean & recreate library dir
rm -rf "$LIBDIR" 2>/dev/null || true
mkdir -p "$(dirname "$LIBDIR")" 2>/dev/null || true

# Recreate work library
vlib "$LIBDIR"

# Map logical "work" to LIBDIR (only needed if LIBDIR != ./work)
if [[ "$LIBDIR" != "work" ]]; then
  vmap -del work 2>/dev/null || true
  vmap work "$LIBDIR"
fi

# Compile
vlog -sv -work work \
  dp_ram.sv \
  mbist_core_v3.sv \
  mbist_csr_wrap_v3.sv \
  tb_mbist_csr_wrap_v3.sv

# Run (save a log)
vsim -c -l vsim_mbist.log work.tb_mbist_csr_wrap -do "run -all; quit -f"

echo "[Questa] Done. Log: $ROOT_DIR/vsim_mbist.log"

