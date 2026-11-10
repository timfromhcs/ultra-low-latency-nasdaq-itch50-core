---
name: chiplab-verify
description: Verify the ChipLab repository end to end (lint, RTL regression, model, cocotb, WASM cross-check, MCP, local cloud, Vercel API) and report a scorecard. Use when asked to prove the repo is green or to diagnose a failing gate.
---

# Verify ChipLab

## Quick gate

```bash
node scripts/gate.mjs          # portable, 11 checks
node scripts/gate.mjs --deep   # 13 checks: + Z3 formal + native bins (WSL on Windows)
```

The gate includes: model tests, WASM smoke, WASM fixture cross-check, backend
compare, MCP smoke, cloud API, web smoke, SBOM, release check, docs links, Vercel API;
`--deep` adds the Z3 formal proof and native-bin check.

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
make cocotb                     # 19 suites: parser, Mold, pipeline, multi-frame,
                               # book, book+snapshot, arbiter, A/B system, recovery,
                               # skid, metrics, host/wishbone/Caravel wrappers
```

Expected: 0 lint warnings, 50k/1M records with 0 mismatches, Z3 PASS, all cocotb
suites PASS. Ubuntu runners use Icarus for cocotb (Verilator/cocotb ABI mismatch);
local WSL can use Verilator.

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
- Multi-frame MoldUDP64 back-pressure, the A/B arbiter recovery and the RTL top-of-book
  are **done**; do not describe them as open.
- Parser P&R/DRC/LVS is still blocked (clock planning + fitted floorplan); the published
  Sky130 pre-PnR STA is WNS −9.14 ns at 3.10 ns (≈81 MHz) and is **not** a sign-off.
  The small `itch_metrics` block did complete the full flow (0 DRC, 0 LVS, 10 ns).
- No Fmax/tapeout claim without LibreLane/OpenSTA output for the block in question.
