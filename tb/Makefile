RUN_DIR = /tmp/itch_workspace
VECTORS ?= vectors

all: sim

sim:
	rm -rf $(RUN_DIR)
	mkdir -p $(RUN_DIR)/rtl $(RUN_DIR)/tb
	cp -r ../rtl/* $(RUN_DIR)/rtl/
	cp -r * $(RUN_DIR)/tb/
	@if [ -d "$(VECTORS)" ]; then rm -rf $(RUN_DIR)/tb/vectors; cp -r "$(VECTORS)" $(RUN_DIR)/tb/vectors; fi
	cd $(RUN_DIR)/tb && verilator -Wall -Wno-DECLFILENAME --coverage --cc -I../rtl ../rtl/itch_top.sv --top-module ultra_low_latency_nasdaq_itch50_cutthrough --exe sim_main.cpp
	cd $(RUN_DIR)/tb && make -j -C obj_dir -f Vultra_low_latency_nasdaq_itch50_cutthrough.mk Vultra_low_latency_nasdaq_itch50_cutthrough
	cd $(RUN_DIR)/tb && ./obj_dir/Vultra_low_latency_nasdaq_itch50_cutthrough --vectors vectors
	cp $(RUN_DIR)/tb/sim_coverage.dat . 2>/dev/null || true
	verilator_coverage --write-info coverage.info sim_coverage.dat 2>/dev/null || true
	verilator_coverage sim_coverage.dat 2>/dev/null || true

clean:
	rm -rf $(RUN_DIR) coverage.info sim_coverage.dat
