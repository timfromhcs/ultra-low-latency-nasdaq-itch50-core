# =============================================================================
# ChipLab â€” one-command targets (Linux/macOS/WSL; Windows via WSL or npm scripts)
# =============================================================================
SHELL := /bin/bash
PYTHON ?= python3
NODE ?= node
WASM := web/wasm/chiplab_core.wasm

.PHONY: help all verify verify-fast verify-deep vectors lint formal formal-all sim cocotb \
        synth-book wasm web backend mcp exe docker demo native test clean

help:
	@echo "ChipLab targets:"
	@echo "  make verify-fast  lint + Python model + WASM + backend + MCP + Vercel (portable)"
	@echo "  make verify-deep  + 1M RTL regression + formal matrix + native bins"
	@echo "  make vectors      generate 100k vectors for the RTL regression"
	@echo "  make lint         Verilator lint (0 warnings)"
	@echo "  make sim          full-field Verilator regression (needs vectors)"
	@echo "  make formal       Z3 BMC + k-induction + covers"
	@echo "  make formal-all   every available SMT solver"
	@echo "  make cocotb       Python/Verilator Cocotb suite"
	@echo "  make synth-book   Yosys area estimate for the BBO (reduced config)"
	@echo "  make wasm         rebuild the 50 KB WASM core"
	@echo "  make web          build/test the static web app"
	@echo "  make backend      run the local Node server (PORT=4173)"
	@echo "  make mcp          run the MCP server"
	@echo "  make exe          build dist/chiplab.exe"
	@echo "  make docker       build the Docker image"
	@echo "  make native       build the Vulkan/DX12 runner"
	@echo "  make clean"

all: verify-fast

verify-fast: lint
	$(NODE) scripts/gate.mjs

verify-deep: verify-fast
	$(PYTHON) tb/itch_model.py --count 1000000 --out tb/vectors_1m
	$(MAKE) sim VECTORS=tb/vectors_1m
	$(NODE) scripts/gate.mjs --deep

vectors:
	$(PYTHON) tb/itch_model.py --count 100000 --out tb/vectors

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/itch_top.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/moldudp64_pipeline.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/itch_top_of_book.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/itch_top_book.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl rtl/axis_skid_buffer.sv

sim:
	$(MAKE) -C tb sim VECTORS=$(abspath $(VECTORS))

formal:
	./formal/run_formal.sh z3

formal-all:
	./formal/solver_matrix.sh

cocotb:
	$(PYTHON) tb/run_cocotb.py
	$(PYTHON) tb/run_mold_cocotb.py
	$(PYTHON) tb/run_pipeline_cocotb.py
	$(PYTHON) tb/run_multi_cocotb.py
	$(PYTHON) tb/run_book_cocotb.py
	$(PYTHON) tb/run_book_top_cocotb.py
	$(PYTHON) tb/run_skid_cocotb.py

synth-book:
	./scripts/synth_book.sh

wasm:
	cd wasm-core && cargo build --target wasm32-unknown-unknown --release
	cp wasm-core/target/wasm32-unknown-unknown/release/chiplab_core.wasm $(WASM)

web:
	$(NODE) scripts/build_vercel.mjs
	$(NODE) scripts/test_vercel_api.mjs

backend:
	$(NODE) backend/server.mjs

mcp:
	$(NODE) mcp/server.mjs

exe:
	$(NODE) scripts/build_exe.mjs

docker:
	docker build -t chiplab:0.2.0 .

native:
	cd native && cargo build --release

test:
	$(PYTHON) -m pytest -q tb/test_model.py
	$(NODE) scripts/wasm_smoke.mjs
	$(PYTHON) scripts/check_wasm_fixture.py
	$(NODE) mcp/client_smoke.mjs

clean:
	rm -rf formal/work_* tb/vectors tb/vectors_1m dist public node_modules native/target wasm-core/target
	@echo "cleaned build artefacts (reports and sources are kept)"

