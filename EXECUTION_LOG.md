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

## 2026-11-03 07:59 - Autonomy tick

- `node scripts/autonomy.mjs` ran 1 task: `formal-z3` -> PASS (no failures to fix).
- Context: v0.3.0 Local Cloud work is in progress and uncommitted; no long work started in this tick.

## v0.3.0 - Local Cloud release work

- Version unified to 0.3.0 (root/npm/native/wasm/pyproject/MCP/SBOM); WASM ABI 0x000300.
- `backend/store.mjs` + `/api/cloud/info` + `/api/store[/:ns]`; CLI `--host/--port/--token/--data-dir`.
- `scripts/test_cloud_api.mjs`: 401, revisions, 409, traversal 400, oversize 413, list, delete.
  Gate now runs 10 checks.
- Web local-cloud panel wired (Test/Sync/Pull); auto-connects only when served by the local service.
- Fixed service worker caching `/api` 404s (cache v4) and mobile overflow of the cloud key/value list.
- MCP expanded to 12 read-only tools with strict schemas and a fixed docs catalog.
- `release.yml` + `scripts/checksums.mjs`; CHANGELOG 0.3.0; README stable-release section.
- EXE rebuilt (83.7 MB) and verified: 401 without token, PUT/GET with token, 400 traversal.
- npm tgz + Python wheel/sdist built and installed in clean dirs; both self-check OK.
- Docker image built; writes require `CHIPLAB_TOKEN` (bridge is non-loopback) and that works.
- UI verified at 390 and 1440 px: run -> sync -> clear -> pull round-trip (revision 4).
- Accessibility audit on the live site: all inputs labelled, buttons named, images alt,
  contrast 5.85 (muted) / 10.59 (accent).
- Published GitHub Release v0.3.0 with 6 assets; Vercel production READY.
- Post-release: restored README UTF-8 (double-encoding from a PowerShell rewrite),
  added 3 project skills, and made the cloud probe use `/api/health` first so the
  Vercel deployment no longer logs a 404.

## 2026-11-03 08:59 - Autonomy tick

- `node scripts/autonomy.mjs`: queue exhausted, ran 0 tasks.
- Continuing Phase 1 (R1): multi-frame MoldUDP64 handoff in `rtl/`.

## R1 resolved - MoldUDP64 multi-frame

- Root causes: `tlast` cleared while a beat was held; a presented beat could be dropped
  without a handshake; `frame_start` was not handshake-qualified; no `tlast` when the
  last byte landed on a full beat.
- Fixes: hold `tvalid/tdata/tkeep/tlast` until `tready`; `final_emit` marks the true last
  beat; handshake-qualified `frame_start`/`frame_end`; depacketizer derives `tlast` from
  its own message counter and discards trailing padding.
- Proof: `tb/test_mold_multi.py` - 5 frames back-to-back (4 valid, 1 gap, 1 dropped
  port) -> 28 records, 1 gap pulse, 1 drop pulse, 0 mismatches.
- Single-frame, header-filter, skid, lint: PASS. Gate 10/10, release_check 14/14.
- CI and Makefile now run the multi-frame test; docs/README/plan updated.

## Phase 1b - RTL top-of-book (functional reference)

- Added `rtl/itch_top_of_book.sv`: direct-mapped per-locate BBO cache + 256-entry order
  table; handles A/F/E/C/X/D/U/P/Q; recounts the best level on any event that touches it.
- Added `tb/test_book.py`: 400 random events vs. an independent Python model ->
  0 mismatches, 33 rescans, 0 overflows.
- Documented limits: input stalls while rescanning (up to 256 cycles), 16-locate direct
  map, parallel ref lookup (not yet BRAM/hash).
- `make lint` and the Icarus cocotb suite include the new module and test.

## Phase 1c - BBO without rescan stall

- Replaced the rescan FSM with a per-locate price-level table (16 bid + 16 ask) updated
  directly on add/execute/cancel/delete/replace.
- BBO is a 16-way max/min reduction, 2 cycles after the event; `s_ready` stays high.
- New proof: 100 events back-to-back at 1 event/cycle, no stall (`tb/test_book.py`).
  The 400-event random test still passes with 0 level/table overflows.
- Remaining timing cost: the 256-way parallel ref lookup (hashed BRAM table next).

## Phase 1d - BBO order lookup

- Replaced the 256-way parallel ref compare with a 4-way set-associative bank
  (64 sets x 4 ways, index = ref[5:0]); 4 comparators instead of 256.
- Same test suite still passes: 400 random events + 100 back-to-back, 0 overflows.
- Remaining: physical timing sign-off of the level table + reduction (Phase 2).

## 2026-11-03 09:59 - Autonomy tick + Phase 2 start

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI green on `c92b1af` and `6ceb711`.
- Ported the BBO init to phase counters (parameterizable table sizes).
- Yosys area estimate: `scripts/synth_book.sh` -> `reports/synth_book.json`.
  Reduced 32/4/4 config: **62,017 cells**, 0 memories. Explicitly **not** a timing
  sign-off; the table sizes and 64-bit shares dominate area.
- Full Yosys logs are git-ignored; only the compact JSON is committed.
- Added `make synth-book`.

## Phase 1e - Parser -> BBO integration

- Added `rtl/itch_top_book.sv`: parser + BBO, parser held in reset until the BBO init
  completes so no message is lost.
- Fixed U (replace) semantics: the replacement inherits the original order's side
  (ITCH U has no side field) and is inserted under the new ref's hash set.
- Added `tb/test_book_top.py`: 152 raw ITCH messages -> 0 mismatches.
- `make lint` and CI now cover the wrapper and the new test.

## 2026-11-03 10:59 - Autonomy tick + formal toolchain fix

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `3f80017` green.
- The manually triggered `Formal` workflow failed: the deep proof on Ubuntu 24.04
  (apt `yosys`/`z3`) reported a counterexample at step 6, while the same proof passes
  locally with Yosys 0.52 + Z3 4.13.3 and in the later solver-matrix run.
- Fix: pin the weekly formal job to **oss-cad-suite 2026-11-03** (Yosys + Z3 bundle)
  instead of Ubuntu's older packages. Mutation job passed (9/9).
- With the pinned bundle, Yosys 0.70 requires `async2sync` before `write_smt2`; added.
  That exposed a genuinely invalid invariant: pre-trigger (combinational) was compared
  with the registered locate, which only matches when the window is stable.
- Replaced it with a provable gating invariant (prefetch only for a known, non-corrupt
  opcode with non-zero length); the other invariants are unchanged. Local proof PASS.
- Root-cause note: toolchain drift plus a too-strong property, not an RTL regression.
- Verified on the runner: deep proof (BMC 20 + k-induction + covers) **success** with
  oss-cad-suite 2026-11-03; mutation job success (9/9).
- The full solver matrix was re-running every solver at depth 20 and would blow the job
  timeout, so it is now **opt-in** via `workflow_dispatch` input `solver_matrix` (capped
  at 20 min). Weekly runs execute the pinned deep proof only.

## Phase 2a - Mutation testing for the BBO path

- Added `tools/mutate_book.py`: patches a copy of `rtl/` and runs the parser->BBO
  test for each mutant; KILLED = test fails.
- 9 mutants (replace side, replace slot, cancel bid/ask, bid max, ask min, volume,
  last price, stored side) -> **9/9 killed (100%)**, `reports/mutation_book.json`.
- Added `make mutate-book` and a weekly `mutation` job in the `Formal` workflow.

## v0.3.1 - patch release

- The 0.3.0 Python wheel shipped `__version__ = "0.2.0"`; fixed and rebuilt.
- `scripts/version.mjs` now syncs `package-lock.json`, Python `__version__`, the Vercel
  health endpoint and `backend/version.mjs` (runtime version for server + EXE).
- `scripts/sbom.mjs` reads the WASM version from package.json.
- `release_check` now checks 14 invariants.
- `docker-compose.yml`: 0.3.1, `CHIPLAB_TOKEN`, persistent `chiplab-data` volume.
- The first v0.3.1 tag was cancelled mid-release and re-tagged at `d67fc87` after the
  runtime version fix; no partial release was published.
