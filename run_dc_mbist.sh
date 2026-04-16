#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Design Compiler run for synth_mbist_wrap_v3.tcl
# Usage:
#   ./run_dc_mbist.sh
#
# Optional clean:
#   CLEAN=1 ./run_dc_mbist.sh
# ------------------------------------------------------------

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "[DC] Project root: $ROOT_DIR"

if [[ "${CLEAN:-0}" == "1" ]]; then
  echo "[DC] CLEAN=1 -> removing dc_work/ (and optional temp DC files)"
  rm -rf dc_work 2>/dev/null || true
fi

# Run DC and capture log
dc_shell -f synth_mbist_wrap_v3.tcl | tee dc_wrap.log

echo "[DC] Done. Log: $ROOT_DIR/dc_wrap.log"
echo "[DC] Reports should be under: $ROOT_DIR/dc_out/ (per your TCL script)"

