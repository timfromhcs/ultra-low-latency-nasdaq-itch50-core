#!/usr/bin/env bash
# =============================================================================
# File: scripts/synth_book.sh
# Description: Yosys area estimate for itch_top_of_book. This is NOT a timing
#              sign-off; it reports cells/DFFs for a reduced configuration.
#              The full log stays out of git; a compact JSON summary is written
#              to reports/synth_book.json.
#
#   ./scripts/synth_book.sh                # ORDERS=32 LOCATES=4 LEVELS=4
#   ORDERS=64 LOCATES=8 LEVELS=8 ./scripts/synth_book.sh
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

ORDERS="${ORDERS:-32}"
LOCATES="${LOCATES:-4}"
LEVELS="${LEVELS:-4}"
OUT="reports/synth_book_${ORDERS}_${LOCATES}_${LEVELS}.log"

yosys -p "read_verilog -sv -Irtl rtl/itch_pkg.sv rtl/itch_top_of_book.sv; \
chparam -set ORDERS ${ORDERS} -set LOCATES ${LOCATES} -set LEVELS ${LEVELS} itch_top_of_book; \
synth -top itch_top_of_book -flatten; abc -g cmos4; stat" > "${OUT}" 2>&1
rc=$?

cells=$(grep -E "Number of cells:" "${OUT}" | tail -1 | awk '{print $NF}')
wires=$(grep -E "Number of wires:" "${OUT}" | tail -1 | awk '{print $NF}')
bits=$(grep -E "Number of wire bits:" "${OUT}" | tail -1 | awk '{print $NF}')
mem=$(grep -E "Number of memories:" "${OUT}" | tail -1 | awk '{print $NF}')

cat > reports/synth_book.json <<EOF
{
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "yosys": "$(yosys -V | head -1)",
  "config": { "ORDERS": ${ORDERS}, "LOCATES": ${LOCATES}, "LEVELS": ${LEVELS} },
  "cells": ${cells:-0},
  "wires": ${wires:-0},
  "wireBits": ${bits:-0},
  "memories": ${mem:-0},
  "note": "Area estimate only; no timing/DRC/LVS sign-off. Full log: ${OUT}"
}
EOF

echo "rc=${rc} -> ${OUT}"
echo "cells=${cells:-0} wires=${wires:-0} bits=${bits:-0} memories=${mem:-0} -> reports/synth_book.json"
exit ${rc}
