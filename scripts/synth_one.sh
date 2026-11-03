#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
W="${1:-128}"
yosys -p "read_verilog -sv -Irtl rtl/itch_pkg.sv rtl/itch_drop_gate.sv rtl/itch_parser_core.sv rtl/itch_shifter.sv rtl/itch_top.sv; chparam -set DATA_WIDTH ${W} ultra_low_latency_nasdaq_itch50_cutthrough; synth -top ultra_low_latency_nasdaq_itch50_cutthrough -flatten; abc -g cmos4; stat" > "reports/synth_${W}.log" 2>&1
echo "rc=$?"
tail -20 "reports/synth_${W}.log"
