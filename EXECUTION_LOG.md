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

## 2026-11-03 23:55 - GF180 pre-PnR STA

- Ran `openlane/gf180.json` with `-p gf180mcuD` to `OpenROAD.STAPrePNR`: setup
  **WNS −19.87 ns**, Fmax estimate **43.54 MHz** (ss/125 °C/4.50 V), worst path
  FF → `raw_order_data[260]`. Published as `reports/openlane_gf180-sta.json`.
- README/openlane tables updated. IHP SG13G2 run started next.

## 2026-11-03 23:45 - Sky130 pre-PnR STA at 250 MHz and 322 MHz

- Ran `openlane/sky130_250mhz.json` to `OpenROAD.STAPrePNR` (57 s after PDK cache):
  setup WNS **−8.27 ns** (ss/100C/1.60 V), TNS −22,463 ns, 19,936 instances,
  199,739 µm². Fmax estimate **81.47 MHz**.
- Existing 3.10 ns run's pre-PnR STA: WNS **−9.14 ns**, TNS −25,193 ns → Fmax
  ≈81.6 MHz. Worst path in both: a shifter counter FF → `raw_payload[0]`
  (asynchronous bypass), so the limit is the bypass/decoder logic, not pipeline depth.
- `scripts/openlane_summary.mjs` now also publishes the worst-path startpoint/endpoint
  and `reports/openlane_sky130-250mhz-sta.json` (6.5 KB) is committed. Clearly labeled
  pre-PnR, not a sign-off.
- The full 3.10 ns P&R run is still active (post-CTS resizer, ~1 h).

## 2026-11-03 23:35 - Host book snapshot block

- Added `rtl/itch_book_snapshot.sv`: per-locate (16) top-of-book, last trade, volume
  and top-4 depth, updated from the book output; registered read port with
  `snap_valid`, `snap_hit`, full 16-bit locate and an `updates` counter.
- New test `tb/test_snapshot.py` (+ runner): locate 1/2 read back, miss on an
  un-updated locate, snapshot stable across unrelated updates, re-read after update
  → PASS, updates=4. Lint clean.
- Wired into `make lint`, `make cocotb` and CI; docs/README/roadmap updated.

## 2026-11-03 22:59 - Autonomy tick + LibreLane summary tool

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate 10/10; CI on `2f8ed55` green.
- Full Sky130 run still active (passes floorplan/placement/CTS; around step 37/80 after
  ~51 min). No result yet.
- Added `scripts/openlane_summary.mjs` + `make openlane-summary`: reads the newest
  `openlane/runs/*/final/metrics.json`, writes a compact `reports/openlane_<tag>.json`
  (die/core bbox, instances, area, setup/hold, DRC/LVS) and prints a summary. Verified
  against a synthetic metrics file; real run output pending.

## 2026-11-03 23:20 - LibreLane 3 config hygiene

- Replaced deprecated/unknown keys in all four `openlane/*.json`:
  `DESIGN_IS_CORE`→`PDN_MULTILAYER`, `PL_TARGET_DENSITY`→`PL_TARGET_DENSITY_PCT`
  (60), `SYNTH_MAX_FANOUT`→`MAX_FANOUT_CONSTRAINT`, `SYNTH_BUFFERING`→
  `SYNTH_ABC_BUFFERING`; dropped unknown `CELL_PAD` and `META`.
- The full Sky130 run (`--run-tag chiplab-sky130`) started with the previous file and
  is still running; result pending.

## 2026-11-03 23:10 - LibreLane toolchain smoke test passed

- Installed LibreLane 3.0.17 in WSL (needed `python3-dev` for `lln-libparse`) and
  pulled `ghcr.io/librelane/librelane:3.0.17` (7.52 GB).
- WSL `--dockerized` failed with "No compatible container engine found" (Docker
  integration not enabled for the distro); ran the container directly from Windows
  Docker with a cached PDK volume instead.
- `librelane --smoke-test`: Classic flow **80/80**, **DRC ✅**, **LVS ✅**, RC 0.
  This is a toolchain check, not a sign-off of ChipLab.
- Added `make librelane-smoke`, documented the verified commands in
  `openlane/README.md`, ignored `runs/`/`openlane/runs/`.
- Started the full Sky130 run of `openlane/sky130.json` (`--run-tag chiplab-sky130`);
  result pending.

## 2026-11-03 22:45 - SLSA provenance for release artifacts

- `exe.yml`: build provenance attestation for `dist/chiplab.exe`
  (`contents: read`, `id-token: write`, `attestations: write`).
- `release.yml`: attestations for the EXE and for the npm tarball / Python wheel /
  sdist; container workflow publishes `provenance: mode=max` + SBOM.
- README documents `gh attestation verify`; roadmap split into SBOM+SLSA (done) and
  reproducible builds/cosign signatures (open).
- Verified end-to-end on run 41713284699 (`exe.yml`, commit `057ca5b`):
  `gh attestation verify chiplab.exe` → **exit 0**, subject sha256
  `5ca234a220eb…`, builder `exe.yml@refs/heads/main`, SLSA provenance v1.
- Container workflow run on `057ca5b` succeeded; `docker buildx imagetools inspect`
  shows the index with an `attestation-manifest` entry (provenance + SBOM).

## 2026-11-03 22:20 - Optional ingress skid stage

- `itch_top_book` parameter `INGRESS_SKID` (default 0) inserts `axis_skid_buffer` on
  the AXI4-Stream ingress for timing isolation at higher clock rates.
- New runner `tb/run_book_top_skid_cocotb.py` rebuilds the same top with
  `-Pitch_top_book.INGRESS_SKID=1` and runs the parser→BBO test. `send_bytes` now
  injects periodic input gaps, so both builds are exercised under stalls.
- Result: identical BBO (152 messages, 0 mismatches), metrics 4800 bytes and
  occ_max 52 in both builds; lint clean. Added to `make cocotb` and CI.

## 2026-11-03 21:55 - Nightly 10M regression

- Added `.github/workflows/nightly.yml` (daily 02:40 UTC): 10,000,000-message
  model→Verilator regression, then the `Formal` workflow as a reusable workflow
  (`workflow_call` added to `formal.yml`).
- Verified locally with the exact workflow commands: generation 2m54s, simulation
  3m06s, **10,000,000 expected records, 0 mismatches**; 200k smoke run 19s.
- Docs/README/CHANGELOG updated.

## 2026-11-03 21:30 - Documentation set (datasheet, integration, errata, API)

- Wrote `docs/datasheet.md`, `docs/integration-guide.md`, `docs/errata.md` (E1–E10)
  and `docs/api.md`; linked from the README and served by `chiplab.docs`, whose
  catalog is now 12 fixed keys (no arbitrary paths).
- Marked the stale tag checkbox in `STABLE_RELEASE_PLAN.md` (v0.3.0/v0.3.1 published).

## 2026-11-03 20:59 - Autonomy tick + performance counters

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `0c24d10` (multi-gap) green.
- Added `rtl/itch_metrics.sv`: message/byte totals, gap/drop pulses, cycle counter,
  max occupancy, 8-bin inter-message gap histogram.
- Fixed the metrics test timing: controlled histogram `[1,2,1,1,1,1,1,1]` PASS.
- Wired `itch_metrics` into `itch_top_book` (`metrics_*`); parser→BBO test now also
  asserts 152 messages, 4800 bytes, histogram sum 152, occupancy 52.
- Added `rtl/itch_metrics.sv` to `make lint` and `run_metrics_cocotb.py` to `make cocotb`
  and the CI cocotb list.

## 2026-11-03 19:59 - Autonomy tick + multi-gap recovery

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `659957e` green.
- New `test_recovery_multi_gap`: lose frame 3, then frames 6+7; each loss is repaired by
  replaying the requested range. Output markers [1..8], 2 requests, 0 abandons.
- The test acts as the replay source; the arbiter's request interface
  (`req_valid/req_seq/req_count`) is the hardware contract for an upstream retransmitter.

## 2026-11-03 19:18 - Autonomy tick + arbiter recovery mode

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `b652e2f` (sequence
  recovery module) green.
- Added `recovery_en` to `mold_feed_arbiter`: on a forward gap it requests the missing
  range (`req_seq`/`req_count`), drops both out-of-order frames, accepts the replay in
  order, and falls back to `abandon` + force-accept after a 256-cycle timeout.
- Exposed the recovery signals through `mold_ab_system` (`cfg_recovery_en`,
  `req_*`, `abandon`, `requests`, `abandoned`).
- New arbiter test: markers [1,2,3,6], 2 requests, 1 abandon; existing selection test
  still passes.

## 2026-11-03 17:59 - Autonomy tick + sequence recovery

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `9a079ef` (pipeline
  back-pressure) green.
- Added `rtl/mold_recovery.sv`: in-order accept, missing-range request
  (`req_seq`/`req_count`), replay recovery, timeout resync (`abandon`), duplicate
  rejection, gap/recovered/abandoned/duplicate counters.
- Test `test_recovery`: 4 accepts, 2 gaps, 1 recovered, 1 abandoned, 1 duplicate.
- Not yet wired to the A/B arbiter; documented as the next integration step.

## 2026-11-03 16:59 - Autonomy tick + Mold pipeline back-pressure

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `258e66a` (A/B system) green.
- Added `m_axis_tready` to `moldudp64_depacketizer` and `moldudp64_pipeline`; the
  depacketizer holds `tdata/tkeep/tlast` until accepted and only consumes when
  `out_ready`. The A/B system now stalls the pipelines instead of relying on the
  arbiter buffer size.
- New `test_output_backpressure`: 329 bytes under random `m_axis_tready`, no loss,
  no reordering. Single-frame, multi-frame and A/B system tests still pass.
- Updated the earlier limitation note: pipeline back-pressure is resolved; only an
  optional skid/FIFO for timing isolation remains.

## 2026-11-03 15:59 - Autonomy tick + A/B system integration

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `a4ce459` (risk checks) green.
- Added frame sequence/count sidebands to `moldudp64_pipeline`.
- Added `rtl/mold_ab_system.sv`: two Mold Ethernet pipelines (independent AXI feeds) ->
  frame arbiter -> one ITCH stream.
- New `test_ab_system`: A/B Ethernet frames with a lagging feed, a tie, a gap and a
  single-feed fallback -> 10 records, 1 gap, byte-exact.
- At that point the pipeline had no downstream tready; fixed in the 16:59 entry.

## 2026-11-03 14:59 - Autonomy tick + BBO risk checks

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `f952c56` (A/B arbiter) green.
- Added optional BBO risk limits: `cfg_max_shares` (order size) and `cfg_collar`
  (price vs. last trade); rejected adds/replaces leave the book untouched and increment
  `risk_rejects`. Wired through `itch_top_book`.
- New `test_risk_checks`: 2 rejects (size, collar), valid add/execute/replace pass;
  book suite now 3 tests, mutation still 9/9.

## 2026-11-03 13:59 - Autonomy tick + A/B feed arbiter

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `b60446b` green.
- Added `rtl/mold_feed_arbiter.sv`: two 2 KB store-and-forward frame buffers, sequence-
  based selection (prefer A on ties), 64-cycle redundancy window, loser discard, gap
  pulse, and byte-exact forwarding.
- Test `tb/test_arbiter.py`: selection [1,2,3,4,7,8], one gap, byte-exact, drops counted;
  the cocotb handshake was corrected to present each beat at the falling edge (a
  double-accept at the buffer-full edge had corrupted the last beat).
- `make lint`/`make cocotb`/CI now include the module and test.

## 2026-11-03 12:59 - Autonomy tick + BBO depth

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Weekly `Formal` run on `d9506ba` **all green**: deep proof, RTL↔WASM equivalence
  (100k), and mutation (9/9).
- Added **top-4 depth** to `itch_top_of_book` (four price levels per side, aggregated
  shares) and wired it through `itch_top_book`.
- Tests updated: 400 random events + 100 back-to-back + 152-message parser→BBO all
  compare the depth; mutation harness still 9/9.

## 2026-11-03 11:59 - Autonomy tick + RTL/WASM equivalence

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- **Formal gate verified green on the runner** (`65d4e47`): deep proof + mutation both
  success; solver matrix now opt-in so the weekly job stays bounded.
- Added `--dump` to `tb/sim_main.cpp` and `scripts/rtl_wasm_equiv.mjs`:
  the RTL and the WASM twin run on the **same** `tb/vectors/stream.bin`;
  **100,000 records, every canonical field equal**.
- `make equiv` and a weekly `equivalence` job in `Formal`; `reports/rtl_records.bin` is
  git-ignored.

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
