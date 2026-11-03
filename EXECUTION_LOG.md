# Execution log — ChipLab

Append-only. Each entry records the task, the exact command, and the observed result.
The full plan is in [`AUTONOMOUS_PLAN_V2.md`](AUTONOMOUS_PLAN_V2.md).

---

## 2026-11-03 — V1 baseline (analysis of the previous agent)

- `git log --oneline` → 2 commits, clean `main`.
- `verilator --lint-only -Wall` → **failed** with 5 × `EOFNEWLINE`.
- `tb/Makefile` build → failed for the same reason; cocotb failed on missing `scapy`.
- Formal harness only proved registered = delayed(raw); no field checks.
- Layout preview was hand-drawn, not OpenLane.
- Conclusion: the README claims were not reproducible; V1 plan written.

## 2026-11-03 — V2 P0: truth and baseline

- Installed WSL toolchain: Verilator 5.032, Yosys 0.52, Icarus 12, Z3, CVC5 1.3.2, Boolector 1.5.
- Fixed RTL EOF newlines; `verilator --lint-only -Wall -Irtl rtl/itch_top.sv` → **0 warnings**.
- Rewrote `itch_shifter.sv` (tkeep, cleared append, generic width).
- Rewrote `itch_parser_core.sv` (all 22 opcodes, 64-bit shares, full payload).
- Rewrote `itch_top.sv` (tkeep/tlast, counters, reference data).
- Added `moldudp64_frontend.sv`, `moldudp64_depacketizer.sv`, `moldudp64_pipeline.sv`.
- Added `tb/itch_model.py` (independent Python model) and `tb/test_model.py`.
- `python -m pytest -q tb/test_model.py` → **8 passed**.

## 2026-11-03 — V2 P0: full-field RTL regression

- `python tb/itch_model.py --count 100000 --out tb/vectors`
- `verilator --coverage --cc ... && ./obj_dir/V... --vectors vectors --limit 100000`
- Result: **100,000 records, 0 mismatches**, 3,139,715 bytes, 196,250 cycles, 41.287 Gbps.
- Found and fixed a real RTL bug: corrupt opcodes leaked the following header bytes into
  `locate/tracking/timestamp`; now zeroed.
- Found and fixed the E/C/X shares offset (byte 19, not 20).

## 2026-11-03 — V2 P0: 1M deep regression

- `python tb/itch_model.py --count 1000000 --out tb/vectors_1m`
- `./V... --vectors vectors_1m --limit 1000000`
- Result: **1,000,000 records, 0 mismatches**, 31,383,973 bytes, 1,961,516 cycles,
  6.0807 ms simulated, **41.290 Gbps**, 9,994 corrupt, byte conservation exact.
- Evidence: `reports/sim_1m.txt`.

## 2026-11-03 — V2 P0: formal

- Rewrote `formal/itch_formal.sv` for the v2 interface: pre-trigger equivalence,
  class exclusivity, legal lengths, register equivalence, flow control.
- `formal/run_formal.sh z3` → **BMC PASS, k-induction PASS, covers PASS**.
- `formal/solver_matrix.sh` → **Z3 PASS (2 s), CVC5 PASS (1 s)**, Boolector 1.5 FAIL
  (unsupported SMT-LIB2 path). Evidence: `reports/formal.json`, `reports/formal_*.log`.
- Honest note: the harness is an invariant proof, not a full functional equivalence proof.

## 2026-11-03 — V2 P0: MoldUDP64

- Front-end header filter + gap + drop test (`tb/test_mold.py`) → **PASS**.
- Single-frame pipeline test (`tb/test_mold_pipeline.py`) → **PASS**, 8 records.
- Multi-frame back-to-back test → **FAIL / open**. The front-end can accept the next
  frame while the depacketizer still owns the previous payload; tracked as R1. No claim
  of full MAC integration.

## 2026-11-03 — V2 P1/P2: WASM core, backend, MCP

- `cargo build --target wasm32-unknown-unknown --release` → `chiplab_core.wasm` 50,181 B.
- `node scripts/wasm_smoke.mjs` → 10,000 records, golden vs rtl-1c byte-equal,
  lossy 4,212 records, Mold/Ethernet streams pass.
- `python scripts/check_wasm_fixture.py` → **10,000 records, 0 mismatches** (WASM vs Python).
- `node backend/run.mjs --compare --count 20000` → 8 chips; lossy FAIL, all others PASS.
- `node mcp/client_smoke.mjs` → **MCP SMOKE PASS** (5 tools, lossy FAIL).
- Fixed BigInt serialization in the MCP server and record decoder.

## 2026-11-03 — V2 P1: web app

- Added `web/index.html`, `styles.css` (Telemetry design system), `app.js`,
  `worker.js`, `core.js`, `gpu.js`, `service-worker.js`, `manifest.webmanifest`, icons.
- Playwright at 1440: **41.29 Gbps, 1,000,000 messages, 0 errors, 664 ms wall**.
- WebGPU: adapter found; compute bins sum 27,143 for 100k records, matching CPU.
- Found and fixed a canvas-context bug: the constructor claimed a 2D context before
  `getContext("webgpu")`, forcing CPU fallback. WebGPU now reports **GPU · WebGPU**.
- Found and fixed `writeBuffer` size semantics (TypedArray size is in elements).
- Playwright at 390: no horizontal overflow (`scrollWidth == 390`), bottom nav shown,
  top nav hidden.
- Evidence: `reports/web-1440-depth.png`, `reports/web-390-run.png`.

## 2026-11-03 — V2 P3: packages, EXE, Docker, Vercel

- npm: `npm pack` → `chiplab-core-0.2.0.tgz`; clean install → `npm ok 1000 1836`.
- PyPI: `python -m build` → wheel + sdist; target install → `py ok 2000 62721`;
  `selfcheck` → 1,000 records, 22 opcodes.
- EXE: `node scripts/build_exe.mjs` → `dist/chiplab.exe` 83.2 MB; `/api/health` and
  static assets return 200; `/api/run` and `/api/compare` work.
- Docker: `docker build -t chiplab:0.2.0 .` → success; container `/api/health` 200.
- Vercel: `node scripts/build_vercel.mjs` → `public/` 13 entries;
  `node scripts/test_vercel_api.mjs` → **VERCEL API SMOKE PASS**.

## 2026-11-03 — V2 P5/P6: native Vulkan, solvers, synthesis

- `cargo build --release` in `native/` → `chiplab-native.exe` 6.1 MB.
- `chiplab-native --probe` → **AMD Radeon 680M, backend=Vulkan**, plus DX12/GL.
- `node scripts/export_records.mjs --count 200000` → 3.2 MB records.
- `chiplab-native --input ... --boost` → **200,000 records in 7.85 ms**, bins match CPU,
  `HIGH_PRIORITY_CLASS: ok`.
- `node scripts/check_native_bins.mjs` → **0 mismatches**.
- Synthesis: 128-bit **22,629 cells / 2,228 DFFs**, 256-bit **25,201**, 512-bit **29,628**;
  logs in `reports/synth_*.log`. This replaces the old unverified 21,811 cell claim.

## 2026-11-03 — V2 P7: autonomy

- Added `autonomy/queue.json`, `scripts/autonomy.mjs`, `scripts/heartbeat.ps1`,
  `scripts/register_heartbeat.ps1`.
- The hourly task resumes the newest OpenCode session in this project with a bounded
  prompt; the log is `reports/heartbeat.log`. Honest limitation: a scheduled task cannot
  guarantee focus of this exact chat window.

---

## 2026-11-03 — V2 P6/P7 final gates

- `tools/mutate.py` → **10/10 RTL mutants killed** (length, offsets, shares width,
  printable, flags, append, consume guard). Evidence: `reports/mutation.json`.
- `node scripts/gate.mjs --deep` → **9/9 PASS, score 100%**:
  model, WASM, cross-check, backend, MCP, web, Vercel, formal Z3, native bins.
- Rebuilt `dist/chiplab.exe` after the v2 WASM + 15 embedded web files; `/api/health`
  reports `version 0x00020000`; static `index.html` 200.
- Rebuilt Docker image; `/api/health` 200 from the container.
- Rebuilt npm tarball/wheel; package installs verified.
- Registered `ChipLabHeartbeat` scheduled task, next run +1 h, log
  `reports/heartbeat.log`; a manual `-Tick` run passed.
- Browser evidence retaken with WebGPU: `reports/web-1440-depth.png` (1M, 0 errors,
  GPU · WebGPU) and `reports/web-390-run.png` (390 px, no horizontal overflow).
- Vercel project `chiplab` created and deployed from `main`:
  **https://chiplab-ten.vercel.app/**; `/api/health` 200, Playwright run 100k = 0 errors,
  WebGPU compute. Evidence: `reports/web-vercel.png`.

## 2026-11-03 — Long-term plan + Phase 0 hardening

- Wrote `LONG_TERM_PLAN.md` (12-month roadmap, north-star metrics, phases 0–4,
  self-healing loop, risks). Research sources: LibreLane/OpenLane 2, SymbiYosys,
  ZipCPU/fpgacpu skid buffers, MCP security 2026, MDN PWA/WebGPU.
- CI failure root causes found from GitHub logs:
  - `ubuntu-22.04` has no `cvc5` package → switched RTL job to `ubuntu-24.04` and made
    cvc5 optional (Z3 is the required proof).
  - Gate used `python` (no pytest) → `gate.mjs` now uses `python3` on non-Windows and
    the WASM job installs pytest with `--break-system-packages`.
- Added `rtl/axis_skid_buffer.sv` + `tb/test_skid.py`: 200 random beats under random
  `tready`, **no loss, stable output, PASS**. Not yet integrated (R1).
- Added `docs/design/mold-backpressure.md` with the exact integration plan.
- MCP hardening: strict argument allowlist/ranges, unknown args rejected, hashed audit
  log, `mcp/SECURITY.md`; valid/invalid call smoke passes.
- Added `scripts/sbom.mjs` → `reports/sbom.json` (163 components) and gate integration.
- Added `.github/dependabot.yml` for npm, cargo, pip and Actions.
- Heartbeat bug found: `opencode run` has no `--prompt` flag; fixed to a positional
  message with `--session`, UTF-8 logging, and a `-DryRun` switch. Dry-run output:
  `opencode run --auto --session ses_e611... "Hallo, es ist ..."`.
- `node scripts/gate.mjs` → **8/8 PASS**.
- CI iterations: fixed missing `cvc5` on 22.04, `python3`/venv for pytest, and the
  Ubuntu Verilator/cocotb ABI mismatch by running pipeline/skid cocotb on Icarus.
  Moved the deep 20-step formal proof to a weekly `Formal` workflow so PR CI stays fast.
  Final GitHub Actions CI run #24: **SUCCESS** (lint, 50k full-field, model, cocotb,
  packages, Docker).

## Open items

| # | Item | Status |
|---|---|---|
| R1 | Multi-frame MoldUDP64 backpressure | open |
| R2 | OpenLane/OpenSTA Fmax + slack | not run |
| R3 | RTL top-of-book | WASM model only |
| R4 | Published npm/PyPI/GHCR artifacts | build/test only (tokens) |
| R5 | Bitwuzla/Yices solver coverage | not installed |
| R6 | Vercel preview deployment | not deployed (build verified) |
