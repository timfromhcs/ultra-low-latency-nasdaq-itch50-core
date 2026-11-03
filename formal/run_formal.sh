#!/usr/bin/env bash
# =============================================================================
# File: formal/run_formal.sh
# Description: Run the v2 formal proof with a selectable SMT solver.
#   Usage: ./run_formal.sh [z3|cvc5|boolector|bitwuzla|yices]
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOLVER="${1:-z3}"
DEPTH="${FORMAL_DEPTH:-20}"
WORK="${ROOT}/formal/work_${SOLVER}"
rm -rf "${WORK}"
mkdir -p "${WORK}"
cd "${WORK}"

echo "[FORMAL] solver=${SOLVER}"
yosys -q -p "read_verilog -sv -formal -I${ROOT}/rtl \
  ${ROOT}/rtl/itch_pkg.sv \
  ${ROOT}/rtl/itch_drop_gate.sv \
  ${ROOT}/rtl/itch_parser_core.sv \
  ${ROOT}/rtl/itch_shifter.sv \
  ${ROOT}/rtl/itch_top.sv \
  ${ROOT}/formal/itch_formal.sv; \
  prep -top itch_formal -nordff; \
  write_smt2 -wires design.smt2"

echo "[FORMAL] BMC"
yosys-smtbmc -t "${DEPTH}" -s "${SOLVER}" design.smt2

echo "[FORMAL] K-induction"
yosys-smtbmc -t "${DEPTH}" -i -s "${SOLVER}" design.smt2

echo "[FORMAL] Covers"
yosys-smtbmc -t "${DEPTH}" -c -s "${SOLVER}" design.smt2

echo "[FORMAL] PASS (${SOLVER})"
