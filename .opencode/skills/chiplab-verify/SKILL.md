---
name: chiplab-verify
description: Verify the ChipLab repository end to end (lint, RTL regression, model, cocotb, WASM cross-check, MCP, local cloud, Vercel API) and report a scorecard. Use when asked to prove the repo is green or to diagnose a failing gate.
---

# Verify ChipLab

## Quick gate

```bash
node scripts/gate.mjs          # portable, ~10 checks
node scripts/gate.mjs --deep   # + Z3 formal + native bins (WSL on Windows)
```

The gate writes `reports/scorecard.json` and prints `scorecard: N% (n/m)`.
Never weaken a test to make the gate pass; fix the cause or record the limit.

## RTL and formal (Linux/WSL)

```bash
make lint
python tb/itch_model.py --count 100000 --out tb/vectors
make sim VECTORS=tb/vectors
make formal
./formal/solver_matrix.sh
python -m pytest -q tb/test_model.py
python tb/run_cocotb.py
python tb/run_pipeline_cocotb.py
python tb/run_skid_cocotb.py
```

Expected: 0 lint warnings, 50k/1M records with 0 mismatches, Z3 PASS,
cocotb pipeline and skid tests PASS. Ubuntu runners use Icarus for cocotb
(Verilator/cocotb ABI mismatch); local WSL can use Verilator.

## WASM / web / API / MCP

```bash
node scripts/wasm_smoke.mjs && python scripts/check_wasm_fixture.py
node backend/run.mjs --compare --count 100000
node mcp/client_smoke.mjs
node scripts/test_cloud_api.mjs
node scripts/build_vercel.mjs && node scripts/test_vercel_api.mjs
node scripts/release_check.mjs
```

## Rules

- No claim without a command and a report under `reports/`.
- Multi-frame MoldUDP64 back-pressure is still open (R1): do not report it as fixed.
- No Fmax/tapeout claim without LibreLane/OpenSTA output.
