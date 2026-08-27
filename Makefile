# ============================================================================
# Universal Makefile for ultra-low-latency-nasdaq-itch50-core
# ============================================================================

SHELL := /bin/bash
PYTHON ?= python3

.PHONY: all verify_all lint formal sim cocotb synth docs clean help

help:
	@echo "Available targets:"
	@echo "  make verify_all - Run end-to-end verification, formal proof & synthesis"
	@echo "  make lint       - Run Verilator lint checks on RTL"
	@echo "  make formal     - Run mathematical formal verification (Z3 BMC & K-Induction)"
	@echo "  make sim        - Run 1,000,000-packet stress test & coverage benchmark"
	@echo "  make cocotb     - Run Cocotb Python regression testbench"
	@echo "  make synth      - Synthesize gate-level netlist & extract cell statistics"
	@echo "  make docs       - Generate WaveDrom timing diagrams & KLayout layout preview"
	@echo "  make all        - Run complete verification & synthesis pipeline"
	@echo "  make clean      - Remove build artifacts and temporary files"

all: verify_all

verify_all: lint formal sim cocotb synth docs

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/itch_top.sv
	@echo "[LINT] Verilator lint passed cleanly with 0 warnings."

formal:
	cd formal && yosys -p 'read_verilog -I../rtl -formal ../rtl/itch_pkg.sv ../rtl/itch_drop_gate.sv ../rtl/itch_parser_core.sv ../rtl/itch_shifter.sv ../rtl/itch_top.sv itch_formal.sv; prep -top itch_formal -nordff; write_smt2 -wires design.smt2'
	cd formal && yosys-smtbmc -t 20 -s z3 design.smt2
	cd formal && yosys-smtbmc -t 20 -i -s z3 design.smt2
	cd formal && yosys-smtbmc -t 20 -c -s z3 design.smt2
	@echo "[FORMAL] Mathematical formal verification PASSED (BMC, K-Induction, Cover)."

sim:
	$(MAKE) -C tb sim
	@echo "[SIM] 1,000,000-packet stress simulation PASSED."

cocotb:
	source .venv/bin/activate && $(PYTHON) tb/run_cocotb.py
	@echo "[COCOTB] Cocotb regression PASSED."

synth:
	yosys -p 'read_verilog -Irtl rtl/itch_pkg.sv rtl/itch_drop_gate.sv rtl/itch_parser_core.sv rtl/itch_shifter.sv rtl/itch_top.sv; synth -top ultra_low_latency_nasdaq_itch50_cutthrough -flatten; abc -g cmos4; stat'
	@echo "[SYNTH] Gate-level synthesis and cell mapping completed."

docs:
	source .venv/bin/activate && $(PYTHON) scripts/generate_waveforms.py
	source .venv/bin/activate && $(PYTHON) scripts/render_gds.py
	@echo "[DOCS] Timing diagrams and layout previews generated."

clean:
	rm -rf formal/design.smt2 formal/itch_parser tb/coverage.info tb/sim_coverage.dat /tmp/itch_workspace /tmp/cocotb_build
	@echo "[CLEAN] Cleaned temporary build outputs."