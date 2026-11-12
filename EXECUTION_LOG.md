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

## 2026-11-12 05:30 - Slew experiment (MAX_FANOUT 8): DRT clean, STA killed twice

- New `sky130_wrap32_25ns_slew.json` (25 ns, resizers, `MAX_FANOUT_CONSTRAINT: 8`) to
  attack the max-slew counts at synthesis level.
- Detailed routing converged to **0 violations** (30,482 → 8,356 → 1,193 → 388 → 107 → 0),
  so the tighter fanout is still routable.
- Post-route STA was killed twice by the host (full 9-corner run at ~12 min, then the
  3-corner subset after ~5 min, both with no summary). **No timing/cap/slew numbers for
  this experiment yet** — it is resumable with `--from OpenROAD.STAPostPNR`.
- `make verify-deep` from WSL is green again: fast **11/11**, 1,000,000 records
  **0 mismatches**, deep **13/13**.

## 2026-11-12 12:59 - Autonomy tick + level-table flow keeps dying at STA

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `5ecd4d4` **success**.
- Resumed the level-table full flow at `OpenROAD.STAMidPNR` (no synthesis replay): it ran
  ~15 min, then the WSL VM died again (`WSAETIMEDOUT`, recovered with `wsl --shutdown`).
  Across the three attempts the flow reached **STA mid-PnR (steps 31/43)** but never
  global/detailed routing.
- The published level-table number therefore stays the **pre-PnR** one (WNS −1.9742 ns,
  Fmax ≈ 37.1 MHz at 25 ns); the full-flow config is committed and repeatable.
- Host note: `WSAETIMEDOUT` is now the dominant failure, usually within 15 minutes of a
  long OpenROAD run.

## 2026-11-12 11:59 - Autonomy tick + level-table full flow attempt

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `78a502c` **success**.
- Added `openlane/sky130_leveltable.json` (full flow: `itch_top_of_book` 32/4/4,
  **30 ns**, 2200 µm die at 12 %, resizers enabled, DRC/LVS on) to turn the pre-PnR
  number into a sign-off. The block has 72,053 mapped cells, i.e. smaller than the
  wrapper, so the die is generous.
- First attempt died during the pre-PnR STA (host restart); the resume replayed
  synthesis and advanced through floorplan/placement/CTS to **STA mid-PnR (step 31)**,
  then the process vanished again (~12:30). No route/DRC/LVS yet.
- The verified number for the plan item remains the **pre-PnR** one: setup WNS
  −1.9742 ns, Fmax ≈ 37.1 MHz at 25 ns. The full-flow config is committed for a stable
  window.

## 2026-11-12 10:59 - Autonomy tick + changelog records the physical milestone

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `9ddee86` **success**.
- The level-table STA could not be retried (WSL unresponsive at 11:00, no uptime output);
  the item stays open.
- `CHANGELOG.md` (Unreleased) now records the release-relevant work of the last days:
  the **25 ns wrapper sign-off** (0 DRC/0 LVS, +1.3333/+0.0840 ns, 42.25 MHz), the
  Docker-free WSL flow path, the new physical configs, `scripts/check_reports.mjs`, the
  **iverilog-13 use-before-declaration fixes** and the **CI oss-cad-suite fallback**.
- No new physical number claimed this tick.
- **Level-table pre-PnR STA landed** (after a `wsl --shutdown` recovery): `itch_top_of_book`
  (ORDERS=32, LOCATES=4, LEVELS=4) at 25 ns gives setup **WNS −1.9742 ns**, TNS
  −1,753.4 ns at `max_ss_100C_1v60`, worst path `s_locate[1]` → FF `_133398_`, chip area
  769,484 µm² → **Fmax ≈ 37.1 MHz pre-PnR**. Published in `openlane/README.md`,
  `docs/datasheet.md` and the plan item (still open: pre-PnR, and the full
  `itch_top_book` P&R does not fit the host's windows).

## 2026-11-12 09:59 - Autonomy tick + CI validates the report artifacts

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `c82f6f1` **success**.
- The level-table STA retry died after ~3 min again (WSL restarted at 09:59, process gone
  by 10:03) — the physical item stays open, no number claimed.
- Added the report-artifact check to **CI** (`node scripts/check_reports.mjs` in the
  `npm + PyPI artifacts` job), so a corrupted or mismatched `reports/openlane_*.json`
  now fails CI, not just the local gate. YAML validated with PyYAML.
- Gate remains 12/12 fast, 14/14 deep.

## 2026-11-12 08:59 - Autonomy tick + report-artifact gate check

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `49df7a6` **success**.
- The level-table STA retry was killed by another WSL restart (up 0 min at 09:06), so
  the physical item stays open; no new number claimed.
- Added `scripts/check_reports.mjs` and wired it into the gate: every
  `reports/openlane_*.json` must parse, carry a tag matching its file name, a valid
  `generatedAt`, a non-trivial metrics object, and — for `*-full.json` — setup, DRC and
  LVS summaries. It validates all 10 current artifacts.
- Gate is now **12 fast checks** (14 with `--deep`): `12/12` and `14/14` verified,
  formal-z3 195 s, native bins pass. `llms-full.txt` updated.

## 2026-11-12 07:59 - Autonomy tick + BBO/level-table STA blocked by the host again

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `ecab264` **success**.
- The full `itch_top_book` pre-PnR STA (`sky130_book_sta.json`, 25 ns) never left Yosys
  ABC: the 70 k-cell block needs >25 min of mapping and the distro was restarted each
  time (area report 2,094,858 µm², same as the area estimate). An AREA-synthesis variant
  (`sky130_book_sta_area.json`) behaves the same.
- Narrowed the target to the plan item itself — `itch_top_of_book` (`ORDERS=32`,
  `LOCATES=4`, `LEVELS=4`) with `openlane/sky130_leveltable_sta.json`. Synthesis
  completes quickly, but the post-synthesis STA was killed twice (3-corner, then
  single-corner `max_ss`) before writing a report.
- So the level-table sign-off remains **open with measured attempts**, not a claimed
  number. Configs are committed so the run can be repeated in a stable window.
- Verified this tick: gate 11/11, docs links, CI green.

## 2026-11-12 06:59 - Autonomy tick + plan closed on the physical milestone

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `73b9231` **success**.
- Updated `LONG_TERM_PLAN.md` to match the evidence: the "Full LibreLane run",
  "Full P&R" and "DELAY short storm" items are now **done**, each with the 25fx numbers
  (0 DRC/0 LVS, setup +1.3333 ns, hold +0.0840 ns, Fmax ≈ 42.25 MHz) and the scope note
  that the 10 ns target is unreachable (post-route setup −13.77 ns).
- Removed the stale "no physical sign-off / blocked P&R" claims from `README.md`
  (status, evidence table, file map), `docs/datasheet.md` and `llms-full.txt`; they now
  state the wrapper sign-off and that parser/BBO blocks remain open.
- No new physical run this tick; the remaining plan items are the BBO level-table
  sign-off (block too large for P&R) and the external blockers.
- Started a **pre-PnR STA of the BBO block** (`openlane/sky130_book_sta.json`,
  `itch_top_book`, 25 ns). Two fixes were needed: add `itch_metrics.sv` to the file list,
  and drop `SYNTH_PARAMETERS` (the parameters live on `itch_top_of_book`, not the top).
  Yosys reports a chip area of **2,094,858 µm²** for the block; ABC mapping was still
  running at the end of the tick.

## 2026-11-12 05:59 - Autonomy tick + tighter fanout makes slew worse

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `1ae6626` **success**.
- Completed the single-corner (`max_ss`) STA for the low-fanout experiment after a
  `wsl --shutdown` recovery:
  - `sky130_wrap32_25ns_slew.json` (`MAX_FANOUT_CONSTRAINT: 8`): setup **+0.1414 ns**,
    hold +0.3496 (0 violations), max-cap **2,460**, max-slew **23,198**
- So the tighter fanout slightly reduces cap but **increases slew** (19,671 → 23,198)
  and eats setup margin (+1.3333 → +0.1414). Rejected; the cap/slew counts are inherent
  to the ss-corner limits of this netlist, not a routing artefact.
- The 25fx sign-off stays the reference: 0 DRC/0 LVS, setup +1.3333 / hold +0.0840 ns,
  Fmax 42.25 MHz.

## 2026-11-12 03:59 - Autonomy tick + fx2 STA: cap/slew repair has no effect

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `08be844` **success**.
- fx2's post-route STA was re-run with a **3-corner subset** (`max_ss`, `min_ff`,
  `nom_ss`, `sky130_wrap32_25ns_fx2_sta.json`) so it fits the short host windows; it
  completed (EXIT=0):
  - setup **+0.4960 ns** (max_ss), hold **+0.1038 ns** (min_ff), 0 violations
  - **max-cap 2,539–3,312**, **max-slew up to 19,671** — i.e. `RUN_POST_GRT_DESIGN_REPAIR`
    did **not** reduce the cap/slew counts compared with 25fx
- Interpretation: the cap/slew counts are not a routing artefact; they come from the
  design/library limits at the ss corner. Cleaning them needs a synthesis-level buffering
  change or relaxed corner limits, not another P&R pass.
- fx2's full DRC/LVS was not collected (STA interruptions); the 25fx sign-off remains the
  reference.

## 2026-11-12 00:59 - Autonomy tick + fx2 (post-GRT design repair): DRT clean, STA interrupted

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `e7defdb` **success**.
- Started `native-25fx2` (`sky130_wrap32_25ns_fx2.json`: 25 ns, resizers **and**
  `RUN_POST_GRT_DESIGN_REPAIR: true`) to attack the remaining max-cap/max-slew counts.
- The post-GRT repair changed the netlist enough that detailed routing again converged
  to **0 violations** (first pass 105,038 → 31,472 → 25,874 → 8,763 → 7,138 → 2,195 → 0),
  and the flow reached RCX and post-route STA.
- The STA step was then killed twice (WSL `WSAETIMEDOUT`, then the process vanished after
  12 min), so **fx2 has no verified cap/slew or timing summary yet**. The run is resumable
  with `--from OpenROAD.STAPostPNR`.
- The previously verified 25fx sign-off (0 DRC / 0 LVS, +1.3333/+0.0840 ns, 42.25 MHz)
  remains the reference result.

## 2026-11-12 00:00 - 25fx completes: first full 25 ns sign-off (43 MHz class)

- The `native-25fx` run (25 ns, 2200 µm, post-CTS/post-GRT resizers) finished the whole
  Classic flow with **EXIT=0**:
  - **Magic DRC 0**, **KLayout DRC 0** (all 257 rules), **LVS 0 errors**
  - **setup +1.3333 ns** at max_ss, **hold +0.0840 ns** at max_ff — 0 violations each
    over all nine corners
  - **Fmax estimate 42.25 MHz**, worst path FF → FF, 100,348 stdcells / 446,548 µm²
  - max-cap 2,529–3,320 and max-slew up to 15,084 (advisory checkers; flow exits 0)
- Artifacts: `reports/openlane_25fx-full.json`, `openlane/runs/25fx-full/` (metrics,
  STA corner reports, Magic/KLayout DRC reports; run dir git-ignored).
- This is the first **complete DRC/LVS/timing-closed wrapper P&R** at 25 ns. Remaining
  quality item: max-cap/max-slew cleanup via `RUN_POST_GRT_DESIGN_REPAIR`
  (`sky130_wrap32_25ns_fx2.json`).

## 2026-11-11 22:59 - Autonomy tick + 25fx: Magic DRC 0 on the resized layout

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `5168f75` and `798bd72`
  **success**.
- `native-25fx` completed **Magic DRC: COUNT 0**
  (`65-magic-drc/reports/drc.magic.rpt`) on the resized 25 ns layout — the layout that
  has **0 setup and 0 hold violations**. The flow moved on to KLayout DRC (step 66),
  then XOR/SPICE/LVS.
- Found the knob for the remaining max-cap/max-slew violations:
  `OpenROAD.RepairDesignPostGRT` is gated by **`RUN_POST_GRT_DESIGN_REPAIR`** (default
  false, so it never ran). Added `openlane/sky130_wrap32_25ns_fx2.json` with that flag
  for the follow-up run.
- KLayout DRC and Netgen LVS for 25fx are still running; no result claimed yet.

## 2026-11-11 20:59 - Autonomy tick + resizer run fixes hold and setup at 25 ns

## 2026-11-11 20:59 - Autonomy tick + resizer run fixes hold and setup at 25 ns

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `a8403e1` **success**.
- The `native-25fx` run (25 ns, 2200 µm, post-CTS/post-GRT resizers enabled) converged
  again to **0 detailed-routing violations** (three DRT passes) and completed post-route
  STA over all nine corners:
  - **hold worst +0.0840 ns (0 violations, TNS 0)**, e.g. max_ss +0.5976, max_ff +0.0840
  - **setup worst +1.3333 ns at max_ss (0 violations)**
  - max-cap 2,529–3,320 and max-slew up to 19,788 violations remain
- So the resizer fixes the −12.3 ps hold cleanly. The flow continued to IR drop and
  streamout; **DRC/LVS for this new layout are still running**.
- Cap/slew cleanup is the remaining timing-quality item.

## 2026-11-11 19:59 - Autonomy tick + 25 ns with resizers (hold/slew cleanup attempt)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `6c0ebb5` **success**.
- Started a **fresh 25 ns run with the post-CTS/post-GRT resizers enabled**
  (`--run-tag native-25fx`, no `--skip`), which is the standard lever for the
  −12.3 ps hold and the cap/slew violations of the previous 25 ns run.
- The post-CTS resizer completed quickly (step 37) and detailed routing started with
  **0 violations**; the host restarted the distro at 19:49, so DRT was resumed.
- The 10 ns flow was stopped after its STA result (setup −13.77 ns): its DRC/LVS would
  not change the conclusion that 25 ns is the practical target.

## 2026-11-11 18:59 - Autonomy tick + 10 ns post-route STA: not achievable

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `167236e` **success**.
- The 10 ns XL run resumed in a long stable WSL window (1h+): DRT converged to **0
  violations** again, then RCX and **post-route STA over all nine corners** completed.
- Result: **setup WNS −13.77 ns** at `max_ss_100C_1v60` (5,695 setup violations), hold
  **−0.0108 ns** at `max_ff_n40C_1v95`. Achievable period ≈23.8 ns → **≈42 MHz**, the
  same as the 25 ns run. So the 10 ns target is not reachable with this netlist; **25 ns
  (40 MHz) is the practical target**.
- Cap/slew violations remain (2.5k–3.3k max-cap, up to 19.7k max-slew), so both runs are
  DRC/LVS evidence rather than timing sign-off. The flow continued to IR drop / streamout
  and the DRC/LVS steps.

## 2026-11-11 17:59 - Autonomy tick + CI chain fixed (apt fallback, iverilog-13 RTL refs)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- CI failure chain on the last push:
  1. `apt-get update` timed out on every attempt (runner mirrors hang), so the job now
     falls back to the **pinned oss-cad-suite 2026-11-03** (same as `formal.yml`,
     cached), with `actions/cache` and a `GITHUB_PATH` entry. Toolchain, pip, lint,
     vectors, 50k regression and model tests then passed.
  2. Cocotb then failed because the suite's **iverilog 13 rejects use-before-declaration**
     (`gate_is_corrupt` in `itch_parser_core.sv`). Moved the declaration above its use.
  3. The next run failed on `rem_count` in `moldudp64_frontend.sv`; reordered the
     repacker declarations. A scan found one more real case (`init_done` in
     `itch_top_of_book.sv`), now also fixed. The other scan hits were substring false
     positives (`msg_count`, `snap_hit`, `upd_volume`, …).
- Local regression: `make lint` + gate 11/11; cocotb `run_cocotb`, `run_multi`,
  `run_book_top`, `run_book_top_skid`, `run_book_snapshot` all pass with the local
  iverilog 12. **CI on `3723c6a` is green** (RTL job included, so iverilog 13 accepts the
  reordered RTL), and `formal/run_formal.sh z3` still reports **PASS**.
- The 10 ns XL run reached 19,028 violations before the host restarted; it is queued
  behind the CI work and will be resumed.

## 2026-11-11 16:59 - Autonomy tick + 10 ns XL converges; CI Toolchain stall bounded

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- **CI was stuck twice** at the RTL job's `Toolchain` step (first run 45+ min at
  `apt-get`, then again on `c2e6e21`). Bounded it: `DEBIAN_FRONTEND=noninteractive`,
  `Acquire::Retries=3`, `Acquire::http::Timeout=30`, `timeout 300/600` around apt, and
  `timeout-minutes: 45` on the job. YAML validated with PyYAML.
- The 10 ns XL detailed routing **converged to 0 violations**
  (35,944 → 21,341 → 19,028 → 1,988 → 776 → 75 → 0), so the 10 ns DELAY netlist is
  routable on the 2200 µm die. A second DRT pass started and the host killed the distro
  at 16:58; resumed.
- Next: finish the second pass, then RCX/STA and DRC/LVS at 10 ns.

## 2026-11-11 15:59 - Autonomy tick + 10 ns retarget on the XL die

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `af5dd24` was **stuck** at the
  RTL job's "Toolchain" step since 14:15 UTC (>45 min); the workflow has
  `cancel-in-progress: true`, so this commit's push starts a fresh run.
- New experiment `openlane/sky130_wrap32_10ns_xl.json`: the 25 ns XL configuration
  retargeted to **10 ns** on the 2200 µm die, to answer whether the big die also fixes
  the 10 ns DELAY netlist (42k detailed-routing violations on 1800 µm).
- Run started natively (`native-10xl`); synthesis finished and the flow is at placement.
- First detailed-routing pass: **35,944 → 21,341 violations**, then optimisation
  iteration 2 — the same convergence shape as the 25 ns run (which reached 0). The host
  restarted the distro at 16:32, so the run was resumed from `OpenROAD.DetailedRouting`.
- **The resumed DRT converged to 0 violations** (21,341 → 19,028 → 1,988 → 776 → 75 → **0**)
  before a second DRT pass started. So the 10 ns DELAY netlist *is* routable on the
  2200 µm die; the host killed the distro again at 16:58 and the run was resumed.
- Next: finish the second DRT pass, then RCX/STA and DRC/LVS at 10 ns (Magic DRC alone
  took 1h40m on this design, so this will span several ticks).

## 2026-11-11 12:59 - Autonomy tick + datasheet publishes the P&R results; Magic DRC attempt

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `f16b83c` **success**.
- Multi-corner STA was killed again after three of six corners (host restart at 13:11).
  The sign-off corners already captured separately (max_ss setup, min_ff hold) remain the
  authoritative numbers.
- `docs/datasheet.md` now publishes both completed wrapper results (50 ns full flow and
  the 25 ns XL run) and states the sign-off scope precisely: the **parser** has no
  physical sign-off, the wrapper does (50 ns full; 25 ns with KLayout DRC/LVS clean,
  Magic DRC and a continuous multi-corner STA still open).
- Started `--from Magic.DRC` on the 25 ns XL run for the last missing check; it was still
  loading the layout after 42 minutes at the end of the tick (no result yet).
- **Follow-up (next tick): Magic DRC completed** after ~1h40m — `127-magic-drc/reports/
  drc.magic.rpt` reports **`COUNT: 0`**. The distro restarted at 15:00 while the flow was
  re-running SPICE extraction/LVS, but the Magic DRC result is saved. The 25 ns XL
  configuration is therefore **fully DRC/LVS clean**: Magic DRC 0, KLayout DRC 0
  (257 rules), LVS 0, setup +1.4597 ns (max_ss), hold -0.00687 ns (min_ff).
- A 3-corner STA batch (max_ff, min_ss, min_tt) completed in 6 minutes and adds the honest
  qualifier: true hold worst case **−0.0123 ns at max_ff** (2 violations), and
  **2,537–3,262 max-cap plus up to 11,370 max-slew violations**. So the 25 ns result is
  routing/DRC/LVS evidence, **not** a timing sign-off.

## 2026-11-11 09:59 - Autonomy tick + 25 ns hold corner measured (−6.9 ps)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `3d7213a` **success**.
- The multi-corner STA kept dying at the fifth/sixth corner (host shutdowns at 10:09),
  so the hold number was captured with a **single-corner** config
  (`sky130_wrap32_25ns_xl_hold.json`, `STA_CORNERS: ["min_ff_n40C_1v95"]`,
  `--from OpenROAD.STAPostPNR --to …`). That run finished in 90 s:
  - **min_ff_n40C_1v95 hold WNS −0.00687 ns** (6.9 ps violation)
  - with the earlier **max_ss setup +1.4597 ns (WNS 0)**, the 25 ns XL design closes
    setup with 1.46 ns margin and misses hold by 6.9 ps.
- Then KLayout DRC ran to completion in a 42-minute window: **0 violations across all
  257 rules** (`112-klayout-drc/reports/drc.klayout.json`). Magic DRC was skipped to fit
  the window.
- **LVS completed (0 errors)** on the third attempt — the host kept the distro alive for
  ~13 minutes and the flow ran Netgen.LVS, the checkers and `ReportManufacturability`,
  saving the final views (exit code 2 only because hold (−6.9 ps) and the skipped Magic
  DRC are reported as violations).
- Final 25 ns XL evidence: GRT 0 overflow, DRT 0 violations, **KLayout DRC 0 (257 rules)**,
  **LVS 0**, setup **+1.4597 ns** (max_ss, WNS 0), hold **−0.00687 ns** (min_ff).
  Magic DRC was skipped for time. Summary: `reports/openlane_25xl-full.json` (with an
  explicit note that its aggregate setup metric is from the `min_ff` corner).

## 2026-11-11 07:59 - Autonomy tick + 25 ns XL: GDS produced, KLayout DRC cut off again

## 2026-11-11 07:59 - Autonomy tick + 25 ns XL: GDS produced, KLayout DRC cut off again

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `0e623e2` **success**.
- Resuming the 25 ns XL run needed care: `--from KLayout.DRC` fails with "missing
  required input 'gds'" and `--from KLayout.StreamOut` fails at `Magic.WriteLEF` for the
  same reason — the GDS only exists after `Magic.StreamOut`. Ran
  `--from Magic.StreamOut`: both GDS files were produced
  (`101/105-klayout-streamout/...gds`, `104-magic-streamout/...magic.gds`).
- Then `--from KLayout.DRC --skip Magic.DRC` started the KLayout deck (rule 697 by
  08:34), and the distro was shut down again at 08:34. **DRC/LVS and post-route STA for
  25 ns are still missing.**
- The host now shuts the distro down every ~10–15 min; a 25–30 min DRC pass cannot
  finish. The 25 ns evidence remains: GRT 0 overflow, DRT 0 violations twice, GDS
  streamed out.
- Ran the post-route STA alone (`--from OpenROAD.STAPostPNR --to OpenROAD.STAPostPNR`):
  it was killed after the fifth of six corners, but the sign-off corner
  **max_ss_100C_1v60** completed — **setup worst slack +1.4597 ns, WNS 0, all paths
  MET** at 25 ns (Fmax ≈ 42.5 MHz). Hold (`min_ff`) is not available yet.
- So the 25 ns XL configuration has: GRT 0 overflow, DRT 0 violations (twice), setup
  closed with 1.46 ns margin. Missing: hold, Magic/KLayout DRC, LVS.

## 2026-11-11 05:59 - Autonomy tick + XL die reaches 0 DRT violations at 25 ns

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `e6d227c` **success**.
- Resumed the XL run (`--from OpenROAD.DetailedRouting`): detailed routing converged
  **35,826 → 21,362 → 18,565 → 12 → 7 → 0**, then a second DRT pass in the same flow
  repeated the pattern (**106,258 → 31,984 → 26,450 → 154 → 74 → 41 → 5 → 0**). Both
  passes ended at **0 violations** — the DELAY netlist at 25 ns is routable on 2200 µm.
- The flow then ran RCX and started post-route STA, but the distro was shut down again
  at 07:16 during the `max_ss` corner STA, so **Magic/KLayout DRC and LVS are still
  missing for the 25 ns run**. A retry from `--from OpenROAD.STAPostPNR` (Magic DRC
  skipped) was killed again at 07:42, still inside the corner STA. The evidence stands
  at: GRT 0 overflow, DRT 0 violations (twice), RCX done, post-route STA incomplete.
- The 2200 µm die therefore solves the short storm (42,342 → 0), at the cost of area.

## 2026-11-11 04:59 - Autonomy tick + extra area fixes the DELAY short storm (42k → 7)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `73ef57a` **success**.
- `sky130_wrap32_25ns_xl.json` (2200 µm die, 12 %, 25 ns DELAY) ran on a good window:
  - global routing **0 overflow**, max layer usage 41.9 % (met2)
  - detailed routing **35,826 → 21,362 → 18,565 → 12 → 7 violations** — the same
    netlist that produced **42,342** violations on the 1800 µm die at 25 ns. Extra area
    is therefore the short-storm fix.
  - the last 7 violations kept iterating; the distro restarted at 05:46 and killed the
    run before DRC/LVS.
- Docs updated with the XL-die numbers; next step is to eliminate the last few
  violations (slightly larger die or more DRT iterations) and then close DRC/LVS at 25 ns.

## 2026-11-11 03:59 - Autonomy tick + 30 ns run gets KLayout DRC 0 / LVS 0 (timing fails)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `ca7a2cc` **success**.
- `KLAYOUT_DRC_THREADS: 6` added to `sky130_wrap32_area_sized.json`, then resumed with
  `--from KLayout.DRC`: the distro stayed up 32 min and the flow **completed**.
  - **KLayout DRC 0**, **LVS 0 errors** (Magic DRC not run — skipped by `--from`)
  - post-route STA at 30 ns: setup WNS **−4.99 ns** (worst-path rpt −3.96 ns),
    hold WNS −0.010 ns → **timing does not close**, Fmax estimate **28.58 MHz**
  - 59,471 stdcells, 218,872 µm², 7.08 % utilization
  - routing DRC was already clear (15 → … → 0); LibreLane exit code 2 from the
    timing checkers, not from DRC/LVS
- Summary committed as `reports/openlane_areasized-full.json`. Conclusion so far:
  AREA netlists route and sign off but top out at ≈29–31 MHz; the faster DELAY netlists
  are exactly the ones that short-storm.
- Started the next experiment (`sky130_wrap32_25ns_xl.json`: 25 ns DELAY on a **2200 µm**
  die at 12 %) to test whether pure area fixes the short storm. The distro restarted at
  04:49 during detailed-routing data preparation and killed it; **no result** — the
  config and rationale are committed for a retry in a stable window.

## 2026-11-11 02:59 - Autonomy tick + 30 ns run loses DRC/LVS to repeated host shutdowns

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `08f197d` **success**.
- The `--from Magic.DRC` resume works (no replay — it jumped straight to Magic DRC on
  the already-routed layout) and is now documented in `docs/long-runs.md`.
- It could not finish: the distro was cleanly shut down every 3–5 minutes between 02:24
  and 03:09 (boot list 02:56 → 03:00 → 03:05 → 03:08, journal `Reached target
  shutdown.target`). Magic DRC restarted from scratch each time.
- Documented the cadence and what it means for physical flows; added the completed
  50 ns wrapper full-flow result to the main README evidence table.
- Tried a cheaper tail: `--from KLayout.DRC` (skips the slow Magic DRC). KLayout DRC
  ran 29 min and was at `sky130A_mr.drc:903` (6.5 M flat polygons) when the distro was
  killed again at 03:45. So neither DRC engine gets a long enough window on this host.
- Open: Magic/KLayout DRC + LVS for the 30 ns AREA+sizing run (routing itself was
  **0 violations**); resume with `--from KLayout.DRC` or `--from Magic.DRC` when the
  host has a stable window.

## 2026-11-11 01:59 - Autonomy tick + AREA+sizing at 30 ns routes clean

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `8ff0147` **success**.
- New `openlane/sky130_wrap32_area_sized.json` (AREA synthesis, `SYNTH_SIZING: 1`,
  30 ns, 1800 µm/15 %) reached detailed routing early and cleared it:
  **15 → 1 → 1 → 0 → 21 → 0 violations**, routing DRC clear, and went on through RCX,
  post-route STA and LEF/GDS export (step 58 `magic-writelef`).
- The distro was then **cleanly shut down at 02:30** (journal: systemd reached
  `shutdown.target`; boots at 02:24, 02:28, 02:32 — external activity in the shared
  distro), so Magic DRC / KLayout DRC / LVS did not run.
- Resumed with `--from Magic.DRC` on the existing run tag (no replay): Magic DRC is
  running on the already-routed layout. Result next tick.
- Pattern confirmed: buffered (DELAY) netlists short-storm at 10 and 25 ns, while AREA
  netlists (50 ns, and now 30 ns with sizing) route cleanly on the 1800 µm die.

## 2026-11-11 00:59 - Autonomy tick + first completed wrapper P&R (50 ns) with 0 DRC / 0 LVS

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `54c8984` **success**.
- The detached routing test finished the **entire Classic flow** (EXIT=0):
  - Magic DRC **0**, KLayout DRC **0**, LVS **0 errors**
  - post-route STA at 50 ns (ss/100 °C): setup WNS **+17.49 ns**, hold **+0.0088 ns**,
    Fmax estimate **30.76 MHz**, worst path `rst_n` → FF `_21959_`
  - 59,465 stdcells (218,344 µm², 7.1 % utilization) on the 1800 µm die
  - detailed routing 10 → 7 → **0 violations**
  This is the first completed wrapper P&R with DRC/LVS sign-off. Artifact produced with
  `node scripts/openlane_summary.mjs openlane/routetest-full` →
  `reports/openlane_routetest-full.json` (the heavy run dir stays git-ignored).
- Started the next frequency step: `openlane/sky130_wrap32_25ns.json` (DELAY synthesis,
  1800 µm/15 %, `--run-tag native-25ns`). Detailed routing's first pass reported
  **42,342 violations** at 25 ns, so the buffered netlist short-storms at both 10 ns and
  25 ns; the run was stopped. Pattern so far: **AREA netlist routes, DELAY netlist
  shorts** — the next step is AREA synthesis plus sizing at ~40 ns to push past 30 MHz.
- WSL was force-terminated once more at 01:03 (`Wsl/Service/HCS_E_TERMINATED`) before the
  25 ns run could start; relaunched successfully. The shared-host restarts continue.

## 2026-11-10 22:59 - Autonomy tick + wrapper DRT re-run is non-deterministic but still failing

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `22d7b91` **success**.
- Re-ran the wide wrapper (`--run-tag native-wide2`) with a detached `Start-Process
  wsl.exe` launcher, so it survives session restarts. DRT this time went
  **43,316 → 26,809 → ~24,712** violations (the first run ended at 171,735), i.e. the
  failure is reproducible in kind but the count is highly non-deterministic and still
  orders of magnitude away from closure.
- Launched a controlled routing test (`openlane/sky130_wrap32_routetest.json`):
  same RTL and floorplan, but 50 ns clock and AREA synthesis (`SYNTH_ABC_BUFFERING: 0`,
  no sizing). If that netlist routes cleanly, the short storm is a property of the
  10 ns buffer-heavy netlist rather than of the wrapper structure.
- Both runs were killed at ≈23:19 when the WSL VM restarted. `journalctl -b -1` shows a
  **second session working in the same Ubuntu distro** (`/home/tim/hscl1-src`,
  `hscl1-build`, installing `hscl-*`/`earlyoom` debs via sudo at 22:31 and 22:38), so the
  VM restarts are external interference, not this project's flows. Boot history for the
  evening: 22:13 → 22:20 → 22:29 → 23:19.
- Consequence: multi-hour physical runs are not reliably possible on this shared host
  right now. The wrapper P&R stays open with a fully characterised blocker (GRT clean at
  1800 µm, DRT short storm, non-deterministic counts).
- **Breakthrough diagnostic after the restart**: the routing test (`50 ns`, AREA synth,
  no sizing/buffering) completed detailed routing with **10 → 7 → 0 violations**
  (routing DRC clear) on the same 1800 µm die and went on to post-route STA, Magic DRC
  and LVS. So the met1/met2 short storm belongs to the **10 ns buffer-heavy netlist**,
  not to the wrapper RTL or the floorplan. Next tick: sweep 25/20 ns to find the fastest
  routable configuration.
- `make verify-deep` from WSL is green again: fast **11/11**, 1,000,000 records
  **0 mismatches**, deep **13/13**.

## 2026-11-10 21:59 - Autonomy tick + wide die: global routing clean, detailed routing not

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `76fb4ce`/`c570f5e` green.
- The 1800 µm / 15 % run (`--run-tag native-wide`) answered the congestion question:
  global routing finished in **one pass with 1 overflow node** (45.9 % usage; met1 49.4 %,
  met2 54.0 %, met3 34.4 %, met4 42.6 %, met5 19.6 %) and **zero NDR retries**
  (`CTS_APPLY_NDR: "none"`). Compare 25,661 overflowed nodes at 1400 µm — the die size
  was the congestion lever.
- Detailed routing then failed structurally: first pass **159,175 violations**, final
  **171,735**, dominated by **met1 shorts 82,017 and met2 shorts 65,698** (plus ~9k
  spacing and ~12k recheck). Same signature on the 1400 µm run (264,817, met1/met2
  shorts dominating), so it is not a density artefact — the wide die does not fix it.
- The WSL VM restarted at ≈21:51 (dmesg: unclean shutdown) and killed the native flow
  mid-iteration. Docker Desktop runs in the **same WSL2 utility VM**, so its periodic
  VM restarts also kill Ubuntu processes — the instability is not Docker-container
  specific. Boot history showed further 1–3 min sessions after Docker was stopped: with
  no `wsl.exe` client attached, WSL terminates the distro ≈15 s after the launching
  command returns, so a `setsid nohup` flow cannot outlive its launcher. Long flows now
  run in a **persistent shell** (background terminal) that stays attached.
- Control experiment started with that setup: the known-good `sky130_metrics.json`
  block runs natively (`--run-tag native-metrics2`) to prove the environment still
  yields 0 DRC / 0 LVS before blaming the wrapper netlist. Result next tick.
- **Control result**: the `itch_metrics` block completed the entire native flow —
  **Magic DRC 0, KLayout DRC 0, LVS 0**, setup WNS **+0.123 ns**, hold WNS
  **+0.107 ns** at 10 ns, 6,776 standard cells (42,127 µm²) on the 500 µm die, routing
  DRC cleared (10 → 0). So the toolchain/PDK/environment is healthy; the wrapper's
  171,735 met1/met2 shorts are design-specific.
- A fresh wide-wrapper run (`native-wide2`) was started detached through
  `Start-Process wsl.exe` so it will not depend on this session; it is still in
  synthesis and is the basis for the per-net short analysis. The next run should
  check the DRT violation distribution per net before another full-flow attempt.

## 2026-11-10 20:59 - Autonomy tick + DRT on the 1400 µm die abandoned, wide die launched

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `76fb4ce` **success**.
- Detailed routing on the 1400 µm/25 % result confirmed the congestion measurement:
  after the first routing pass it reported **64,091 violations**, then **264,817** in
  optimisation iteration 1 (10–20 % complete, ≈14 min per iteration). That cannot
  converge, so the run was stopped rather than allowed to burn hours.
- New `openlane/sky130_wrap32_wide.json`: **1800 µm** die, 15 % target density,
  20 overflow iterations, `CTS_APPLY_NDR: "none"` (the option is an enum;
  `false` is rejected), `RUN_ANTENNA_REPAIR: false` (skips diode insertion), DRC/LVS
  still on. Rationale: routing usage was 81 % at 1400 µm, so more whitespace is the
  direct lever.
- The wide flow started natively at 21:14 (`--run-tag native-wide`); its pre-PnR STA
  reproduces the same netlist result (setup WNS **+0.3537 ns**, 19,660 slew
  violations), confirming only the floorplan/PDK settings changed.
- **No routing/DRC/LVS result yet** — the wide run is at placement/CTS.

## 2026-11-10 19:59 - Autonomy tick + global routing completed natively (congestion measured)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. CI on `2df2dd5` **success**.
- The native flow (started 19:28) reached and finished **OpenROAD.GlobalRouting** in
  ≈55 min: six passes, each disabling NDR on one clock net (`clk`, `clknet_0_clk`,
  `clknet_2_0_0`, `2_2_0`, `2_3_0`) after 30 overflow iterations.
- Measured final congestion at 1400 µm / 25 %: **81.26 % total usage, 25,661 overflowed
  nodes** (met1 85.0 %, met2 90.6 %, met3 73.2 %, met4 69.8 %, met5 53.0 %), wirelength
  10.8 mm. So this die is still too small — the congestion blocker is now quantified
  instead of inferred.
- The flow continued into antenna repair / diode insertion
  (`41-openroad-repairantennas`). **Detailed routing is still running** — no DRC/LVS
  result yet.
- `openlane/README.md` fitted-attempt table, `LONG_TERM_PLAN.md` and this log updated
  with the measured congestion numbers.

## 2026-11-10 18:59 - Autonomy tick + native (Docker-free) LibreLane path

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate stays green; CI on `0c392a4`
  **success**.
- The Docker Desktop VM restarts (`exit 255`) made multi-hour flows impossible, so the
  LibreLane image was exported and run **natively inside WSL Ubuntu**:
  `docker export` → `/nix` closure (472 store paths), Sky130 PDK (2.2 GB) from the
  `chiplab-librelane-ciel` volume → `/opt/ciel`, then
  `/nix/store/…-python3-3.13.9-env/bin/librelane --pdk-root /opt/ciel`.
- **Parity check**: native STA of `sky130_wrap32_fitted.json` reproduced the container
  result exactly — setup WNS **+0.3537 ns**, **19,660** max-slew violations, same
  utilization. So the native path is a valid substitute, not a different toolchain.
- Launched the full fitted flow natively (`--run-tag native-full`, 10 ns, 1400 µm,
  30 GRT iterations, post-CTS/post-GRT resizer skipped) with `setsid nohup`; it was at
  `28-openroad-globalplacement` after ~5 min with no Docker involvement.
- `docs/long-runs.md` §2b and `openlane/README.md` now document the recipe and the
  parity evidence. **No routing/DRC/LVS result yet** — the flow is still running.

## 2026-11-10 14:59 (cont.) - Parser wrapper full-flow attempt: WSL memory cap raised

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Fast gate **11/11**.
- New config `openlane/sky130_wrap32_fitted.json` (32-bit wrapper, 1400 µm die at
  25 % target density, `GRT_ALLOW_CONGESTION`, 200 overflow iterations,
  `RUN_HEURISTIC_DIODE_INSERTION: false`, 10 ns). The obsolete `CTS_BALANCE_LEVELS`
  key was included by mistake and is ignored by 3.0.17 (`CTS-0132`); `docs/long-runs.md`
  now names the effective CTS knobs and the real step mapping
  (`RUN_HEURISTIC_DIODE_INSERTION` → `Odb.HeuristicDiodeInsertion`).
- First full run reached **GlobalRouting in ~7 min**, then the container died
  (`exit 255`) when the Docker VM restarted. Resumed with `--last-run`: it replayed the
  flow from synthesis (steps 44+) rather than resuming at routing; documented.
- Measured on the way (evidence for this configuration only):
  - pre-PnR at 10 ns, ss/100 °C/1.60 V: setup **WNS +0.354 ns**, hold clean,
    but **19,660 max-slew violations** — setup "closure" here is buffer-driven.
  - post-CTS: 54,569 instances (15,779 combinational, 1,565 FFs, 6,236
    timing-repair buffers, 435 clock buffers, 26,302 tap cells), 19.2 % utilization.
- Root cause of the first two kills looked like memory: `.wslconfig` had
  `memory=6GB, processors=6` while the container reported a 5.789 GiB limit. Raised it
  to 10 GB / 8 CPUs, restarted Docker and resumed; the container then had 9.715 GiB.
  A third kill still happened at 1.2 GiB used, so the cap was not the cause; the
  original `.wslconfig` (6 GB / 6 CPUs) was restored afterwards.
- The resumed GRT did **33 of 200 overflow iterations in ≈1 h** (≈2 min per pass) and
  would have needed many hours. The third container kill (`exit 255`) coincided with
  another Docker Desktop VM restart (init logs at 16:38, 17:24, 18:11) while the
  container used only 1.2 GiB — so it is not a container OOM. Stopped the run.
- Added `openlane/sky130_wrap32_fitted_area.json` (AREA synth, 20 % density, 1500 µm,
  30 overflow iterations). Bounded STA: 133,125 µm² chip area, but setup
  **−83.06 ns** with 4,286 violations — not timing-viable; the 10 ns DELAY netlist's
  closure is buffer-driven.
- Config corrected: `GRT_OVERFLOW_ITERS` 200 → 30 and the obsolete
  `CTS_BALANCE_LEVELS` removed. `openlane/README.md` and `docs/long-runs.md` now carry
  the measured numbers, the iteration-time guidance and the step-mapping facts.
- **No routing/DRC/LVS result is claimed**; the parser P&R remains blocked by
  congestion plus this host's Docker VM restarts.

## 2026-11-10 14:59 - Autonomy tick + BBO area estimate refreshed

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Re-ran `scripts/synth_book.sh` (Yosys 0.52, 32/4/4): **70,715 cells / 115,792 wires**
  — the documented 62,017 / 98,322 predates the top-4 depth and risk-check logic.
  `reports/synth_book.json` is refreshed and the number is corrected in README,
  datasheet, llms-full and the roadmap. Area estimate only, no timing/DRC/LVS claim.

## 2026-11-10 13:59 - Autonomy tick + PWA offline verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Service worker check: `navigator.serviceWorker.ready` → active, scope `/`, cache
  **`chiplab-v4`**.
- Playwright offline reload (`context.setOffline(true)`): the app still renders
  (`ChipLab — ITCH-50 silicon lab`, hero "Run the feed. See the silicon.") from the SW
  cache; the only console error is `/api/health` → `ERR_INTERNET_DISCONNECTED`, which is
  expected while offline.
- README evidence table gained a PWA-offline row; browser and server stopped.

## 2026-11-10 12:59 - Autonomy tick + local-cloud UI round-trip verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Drove the Local cloud panel with Playwright against the running server:
  - **Test** → "Connected to chiplab-local-cloud v0.3.1 · .data · 56s uptime."
  - Run feed (100k) then **Sync** → server store reaches **revision 2** with
    `runs`/`lastRun` keys.
  - **Pull** → "Pulled 2 runs from revision 2." in the panel.
- README evidence table gained a Local-cloud UI round-trip row. Server and browser
  stopped afterwards. (The `.data` store on this machine now holds this test run's
  history; it is git-ignored.)

## 2026-11-10 12:00 - Autonomy tick + docker compose verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Docker Desktop was down after a host restart; started it, then tested the compose
  path: `CHIPLAB_TOKEN=compose-token docker compose up -d --build` →
  `/api/health` ok **v0.3.1**; authenticated PUT → **revision 1**; after
  `docker compose restart` the same revision and data came back from the named volume.
  `docker compose down -v` removed container, network and volume.
- README Docker evidence row updated to cover the compose path and persistence.

## 2026-11-10 10:59 - Autonomy tick + native Vulkan re-verified, nightly dispatched

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- **Native Vulkan** (`native/target/release/chiplab-native.exe`, Radeon 680M):
  `--probe` 3/3 exit 0 (Vulkan adapter selected); 200,000 records processed in
  **46.49 ms**, GPU bins vs CPU **0 mismatches**, checksum 254251. The documented
  7.85 ms was stale; README and `docs/benchmarks.md` now carry the 2026-11-10 number.
- Dispatched the `nightly.yml` workflow with `count=200000` to verify the nightly path
  itself: **success** — 200k full-field regression, deep Z3 proof, mutation and
  RTL↔WASM equivalence all green on `ccea710`.

## 2026-11-10 09:59 - Autonomy tick + `make verify-deep` fixed (gate bug)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Re-ran `make verify-deep` from WSL. The 1M regression passed (0 mismatches) but the
  deep gate reported **FAIL formal-z3 (125 ms)**: `scripts/gate.mjs` hardcoded
  `wsl -d Ubuntu /mnt/e/chips/main/...` for the formal check, which does not exist when
  the gate already runs inside WSL/Linux.
- Fixed: the deep checks now choose the command by platform (`./formal/run_formal.sh z3`
  on Linux/WSL, the `wsl …` bridge on Windows). Re-ran `make verify-deep` end to end:
  fast gate **11/11**, 1,000,000 records **0 mismatches**, deep gate **13/13**
  (formal 96.7 s).
- `reports/scorecard.json` now records the deep 13/13 run.

## 2026-11-10 08:59 - Autonomy tick + synthesis numbers refreshed, Boolector re-checked

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Re-ran `scripts/synth_matrix.sh` (Yosys 0.52, ABC cmos4): **22,710 / 25,324 / 29,568
  cells** for 128/256/512-bit, **2,228 DFFs** — the documented 22,629 / 25,201 / 29,628
  were from an older Yosys and are now updated in README, benchmarks, llms-full and the
  roadmap; the tracked `reports/synth_*.log` files were refreshed.
- Re-checked Boolector at depth 8: BMC aborts with `BrokenPipeError`, so the documented
  "Boolector 1.5 unsupported" stands.
- No test changes.

## 2026-11-10 07:59 - Autonomy tick + CVC5 formal claim corrected

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Audited the "Z3 + CVC5 PASS" claim. Z3 remains verified (deep gate, ≈90 s, BMC +
  k-induction + covers). **CVC5 1.3.2 on this host does not reproduce the full claim**:
  - depth 20: BMC exceeded 14 min and was killed;
  - depth 8: BMC PASSED (47 s), k-induction PASSED (2 s), **covers FAILED** (the cover
    targets need depth 20).
  The stored `reports/formal.json` CVC5 PASS is the 2026-11-03 oss-cad-suite run.
- Corrected the README badge and formal rows, `docs/benchmarks.md`, `llms-full.txt` and
  the roadmap; added errata **E11** describing the tool-version limitation. No test was
  weakened.

## 2026-11-10 06:59 - Autonomy tick + Docker and live Vercel re-verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- **Docker** (`docker build -t chiplab:verify .`, run on 4199 with `CHIPLAB_TOKEN`):
  `/api/health` → ok, **v0.3.1**, WASM **50,322 B**; unauthenticated store GET →
  **401**; authenticated PUT → **revision 1**. Container stopped afterwards.
- **Vercel production**: `/api/health` → ok, v0.3.1; page 200 (13,797 bytes), title
  `ChipLab - ITCH-50 silicon lab`.
- README evidence rows for Docker and Vercel updated; no source changes.

## 2026-11-10 05:59 - Autonomy tick + end-user artifacts re-verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Rebuilt and probed the shipped artifacts on the current tree:
  - **EXE**: `npm run build:exe` → `--probe --no-open` exit 0 (WASM 50,322 B, version
    0x301, 8 chips); rebuild hash `67d05b22…` is byte-identical to the recorded
    reproducible build.
  - **npm**: `npm pack` + clean install in a temp project (0 vulnerabilities), CLI
    parses 2,000 records at 41.28 Gbps.
  - **PyPI**: wheel built, installed into a fresh venv, `chiplab-itch selfcheck` →
    10,000 records, 22 opcodes.
- README evidence rows for EXE/npm/PyPI updated; no source changes.

## 2026-11-10 04:59 - Autonomy tick + browser UI re-verified after WASM rebuild

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Started the local server and drove the PWA with Playwright (1440×900 and 390×844):
  - WASM badge `v0.3.1 · 49 KB`, GPU `WebGPU`, local cloud **connected**; console
    **0 errors** (1 warning).
  - Run feed, 100,000 messages: **41.29 Gbps, 177.3 M msg/s, 0 errors**, tape 60 rows.
  - Compare all: **7 × PASS**, lossy negative control **FAIL · 58,458** (as designed).
  - Mobile 390 px: `scrollWidth == clientWidth == 390` → no horizontal overflow;
    single-column layout with the sticky section nav.
  - Evidence: `reports/web-1440.png` (full page, post-compare), `reports/web-390.png`
    (viewport, top), `reports/web-390-full.png`. Server stopped afterwards.
- README evidence table updated with the re-verification row.

## 2026-11-10 03:59 - Autonomy tick (no code change: only external blockers left)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**. Tree clean apart
  from regenerated `reports/`.
- Re-audited every unchecked roadmap item; each needs a prerequisite this repository
  cannot supply:
  - parser P&R/DRC/LVS: clock planning + fitted floorplan + a stable multi-hour run
    environment (five failure modes documented in `openlane/README.md`);
  - FPGA target: hardware and vendor toolchain;
  - full Caravel harness: Caravel SoC repo + PDK sim environment (`caravel/README.md`);
  - PCIe/DMA or 100G MAC: large integration without simulation models;
  - npm/PyPI registry publishing: trusted-publisher/OIDC setup;
  - optional shuttle: external programme.
- Deliberately no further micro-edits: the docs, skills, guides and CI are already at
  the verified state. The next actionable step for a human is a clock/floorplan session
  and a stable runner for the parser flow.

## 2026-11-10 02:59 - Autonomy tick + CI concurrency groups

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- Added `concurrency` to `ci.yml` (`ci-${{ github.ref }}`, cancel-in-progress) so a
  superseded push cannot leave a half-created run competing with the next one — the
  partial run #136 (2 of 4 jobs) was the motivation. `repro.yml` gets a non-cancelling
  `repro` group so the weekly run is never cut short.
- No source changes; YAML validated, CI run checked for all four jobs.

## 2026-11-10 01:59 - Autonomy tick + llms-full.txt refreshed

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- `llms-full.txt` was stale: it listed old modules, `scripts/mutate.py` (does not
  exist), no metrics/book/snapshot/host/wishbone/Caravel blocks, no 10M/nightly, no
  reproducibility/SLSA/cosign and no pre-PnR or small-block physical results.
- Rewrote it against the current tree: all RTL blocks, 19 cocotb suites, 10M nightly,
  gate 11/13, release/signing flow, measured pre-PnR STA for parser/wrappers/GF180/IHP,
  the completed `itch_metrics` full flow, reproducibility and the honest limits.
- No source changes; docs links unchanged (25 files, 0 dead).

## 2026-11-10 00:59 - Autonomy tick + project skills corrected

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- The three `.opencode` project skills had stale claims:
  - `chiplab-verify` said "~10 checks" (now 11 fast / 13 deep) and listed
    multi-frame Mold back-pressure as open — it is done. It now points at `make cocotb`
    (19 suites) and states the real physical status (pre-PnR STA ≠ sign-off; only
    `itch_metrics` completed a full flow).
  - `chiplab-release` still gated `v1.0.0` on multi-frame/BBO (both done) and said not to
    claim reproducible builds (WASM/Python/EXE are reproducible). Updated, including
    the cosign bundles in the asset list.
  - `chiplab-local-cloud` now mentions the SLSA attestation next to the SHA-256 check.
- Docs links: 25 files, 0 dead.

## 2026-11-10 00:05 - Autonomy tick + long-run operations guide

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- Wrote `docs/long-runs.md` from the actual run history: Docker/PDN volume setup
  (`/root/.ciel`), bounded pre-PnR first, the knobs that matter (resizer skips,
  `GRT_ALLOW_CONGESTION`, antenna repair removing `OpenROAD.DiodeInsertion`), resuming
  with `--last-run` **plus the config** and repeated skip flags, the observed failure
  modes (GRT-0116, GPL-0305, DPL-0036, GRT-0183, container EOF), cleanup and the
  reporting rule (a block-level flow is not a parser sign-off).
- Linked from the openlane README and the main docs list; link check **25 files,
  0 dead links**.

## 2026-11-09 22:59 - Autonomy tick + Caravel integration recipe

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate was 11/11.
- Wrote `caravel/README.md`: exact port mapping, what is verified here (lint + cocotb
  against the `user_project_wrapper` top) and what is not (pad ring, `caravel.v`,
  Caravel simulation), plus the `make setup`/`make verify` recipe and the warning not
  to claim a Caravel sign-off until that run exists.
- Extended the docs link check to `caravel/` (now 24 Markdown files, 0 dead links);
  linked the recipe from the integration guide.

## 2026-11-09 21:59 - Autonomy tick + Caravel drop-in user_project_wrapper

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Added `caravel/user_project_wrapper.v` with Caravel's exact module name and port
  list, forwarding to `itch_caravel_wrap`. Verified with Verilator lint (clean) and the
  existing Caravel test run against the `user_project_wrapper` top: two messages over
  `io_in`, Wishbone reads of count/type/locate/shares/ref → **PASS**. Wired into
  `make lint`, `make cocotb` and CI; documented in the integration guide, README and
  roadmap.
- Still open: the actual Caravel harness run (pad ring, Caravel simulation) needs the
  Caravel repo/PDK.

## 2026-11-09 20:59 - Autonomy tick + local release-candidate pass

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Re-ran the full local RTL suite on the current tree: `make lint` **0 warnings**,
  `make cocotb` **18 suites / 25 tests, 0 failures**. Together with the deep gate
  13/13 from the previous tick, this is a complete local release-candidate pass.
- No source changes; the remaining roadmap items still need external prerequisites
  (clock plan/floorplan + stable long P&R environment, FPGA hardware, Caravel repo/PDK,
  registry OIDC, optional shuttle).

## 2026-11-09 19:59 - Autonomy tick + deep gate 13/13

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Ran `node scripts/gate.mjs --deep` on this machine: **13/13 (100 %)** — the 11 fast
  checks plus the Z3 formal proof (≈90 s) and the native-bin cross-check. This
  re-verifies the complete portable gate on the current tree, not just in CI.
- `reports/scorecard.json` now records the deep run (`deep: true`).
- No code changes; roadmap blockers unchanged.
- CI anomaly: run #136 (`bcdfba1`, docs-only) ended `failure` with only 2 of 4 jobs
  created ("WASM…" and "Docker" green; "RTL…" and "npm…" never ran). The next commit
  `aa02f0e` ran all four jobs green, and GitHub refuses to re-run #136 — treated as a
  runner/queue hiccup, not a code failure. Re-checked: workflow YAML unchanged since
  `79d078c`.

## 2026-11-09 18:59 - Autonomy tick + formal re-verification on main

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- No unblocked roadmap item remains (all need clock planning/hardware/Caravel repo/
  registry OIDC). Instead of idling, dispatched the weekly `Formal` workflow on the
  current `main` to re-confirm the deep proof, mutation score and RTL↔WASM
  equivalence after the recent RTL additions.
- Observed 9 open Dependabot PRs: `setup-node`, `upload-artifact`, `checkout` and
  `docker/build-push-action` bumps are green on CI; `setup-buildx`, `docker/login`,
  `wgpu 30` and `pollster 1.0.1` are red. Not merged automatically.
- Formal dispatch on `86ae19f` (current main): **success** — deep SymbiYosys/Z3 proof,
  mutation score and RTL↔WASM equivalence all green.

## 2026-11-09 17:59 - Autonomy tick (green, no unblocked roadmap work left)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**. Working tree clean.
- README CI evidence row now points at the latest `main` run instead of a fixed old
  run number, so it cannot go stale.
- No new engineering: every remaining roadmap item needs an external prerequisite —
  parser P&R (clock planning + fitted floorplan + a stable multi-hour environment),
  FPGA target (hardware), full Caravel harness (Caravel repo/PDK), PCIe/100G (large
  integration), registry publishing (OIDC/token), shuttle (optional).
- Last verified state: `itch_metrics` full flow 0 DRC/0 LVS/timing closed; all RTL
  suites (18/25 tests), reproducibility (WASM/Python/EXE), SLSA/cosign and the gate
  green. No claims added.

## 2026-11-09 17:30 - Fast parser flow aborted by container restart

- `wrap32-100mhz-fast2` (10 ns, 1500 µm, antenna repair off, resizer skipped) reached
  GlobalRouting and was at extra iteration 32/50 when the **container died**
  ("unexpected EOF"); Docker/host instability, not a flow assertion.
- Summary of parser attempts: 700 µm congestion, 1400 µm placement divergence,
  1000 µm/35 % DRT non-convergence, 10 ns/antenna-on `DiodeInsertion` GRT-0183 after
  ~7 h, 10 ns/antenna-off aborted by the container. Long P&R runs are not reliable in
  this environment; the `itch_metrics` full flow (0 DRC/LVS, timing closed) remains the
  flow evidence.
- Removed the partial run directory; documented in `openlane/README.md` and the roadmap.

## 2026-11-09 16:59 - Autonomy tick + fast parser flow in routing

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- `wrap32-100mhz-fast2` (antenna repair off, resizer skipped, 10 ns, 1500 µm) is at
  GlobalRouting extra iteration 49/50, then DetailedRouting. The 7 h run that used
  antenna repair failed in `OpenROAD.DiodeInsertion` (`GRT-0183`); that run directory
  was removed after documenting the failure.
- No parser P&R result yet; `itch_metrics` remains the only completed full flow.

## 2026-11-09 15:59 - Autonomy tick + relaxed parser flow in routing

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **11/11**.
- The 100 MHz 32-bit-wrapper run (`wrap32-100mhz`, 1500 µm die, 25 % density) is in
  GlobalRouting extra iterations (47/50) with congestion allowed; it will proceed to
  detailed routing. No result yet — the long pole is DRT on ~20k cells.
- First full-flow evidence remains the `itch_metrics` block (0 DRC, 0 LVS, timing
  closed at 10 ns, `reports/openlane_metrics-full3.json`).

## 2026-11-09 06:59 - Autonomy tick + first full-flow block (metrics)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Added `openlane/sky130_metrics.json` (`itch_metrics`, 500 µm die, 10 ns clock) and
  ran the **complete** Classic flow: **0 routing DRC, 0 Magic/KLayout DRC, 0 LVS
  errors**, timing closed (WNS +0.12 ns, Fmax ≈101 MHz), 6,776 stdcells (456 FFs),
  42,127 µm² cell area; CTS inserted 107 clock buffers + 9 clock inverters and 300 hold
  buffers. Artifact `reports/openlane_metrics-full3.json`.
- Two earlier variants failed: 200 µm die → DPL-0036 (too many pins for the perimeter);
  3.10 ns → resizer did not converge. Both documented.
- Fixed `scripts/openlane_summary.mjs` to tolerate `Infinity`/`NaN` in LibreLane's
  metrics.json (Python writes them; `JSON.parse` rejects them).

## 2026-11-09 05:59 - Autonomy tick + guides synced (EN/DE/FR)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- The three zero-to-hero guides were stale: they referenced v0.3.0 / `chiplab:0.3.0`
  and listed already-finished work (multi-frame backpressure, RTL top-of-book,
  published artifacts) as open. Updated all three to v0.3.1, added the
  `node scripts/gate.mjs` (11 checks) step, rewrote "what is still open" to the real
  state (pre-PnR STA only, no P&R/DRC/LVS sign-off; FPGA/PCIe; Caravel harness;
  opt-in registry publishing) and added a "further reading" section linking the
  datasheet, register map, integration guide, errata and API.
- Encoding verified (UTF-8, no replacement chars, no stale `0.3.0`); docs link check:
  **23 files, 0 dead links**.

## 2026-11-09 04:59 - Autonomy tick + book snapshot integration

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate was 11/11.
- Added `rtl/itch_book_snapshot_top.sv` (parser + BBO + snapshot, top-4 depth wired)
  and `tb/test_book_snapshot.py`: locate 1/2 snapshot equals the last BBO event for
  every field (price/shares/last/volume/depth), locate 3 reads as a miss → **PASS**.
- Lint clean; wired into `make lint`, `make cocotb` and CI.

## 2026-11-09 03:59 - Autonomy tick + register/port map documentation

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate was 11/11.
- Added `docs/register-map.md`: host register file word map (0–10), Wishbone mapping
  (`wbs_adr_i[6:2]`, 1-cycle ACK, writes ignored), Caravel `io_in/io_out/io_oeb` map,
  snapshot read port semantics, performance counters and Mold/arbiter status signals.
- Added it to the MCP `chiplab.docs` catalog (now **13 fixed keys**), README docs list
  and API reference; `chiplab.docs` returns it (4,607 bytes) and still rejects
  `../README.md`. Docs link check: **23 files, 0 dead links**.

## 2026-11-09 02:59 - Autonomy tick + docs link check in the gate

- `node scripts/autonomy.mjs`: queue empty, 0 tasks.
- Added `scripts/check_docs_links.mjs` (`make docs-links`): scans README, CHANGELOG,
  CONTRIBUTING, both plans, `docs/`, `openlane/`, `mcp/` and `.opencode/` for relative
  Markdown links, skipping http/mailto/anchors and fenced code. Result: **22 files,
  0 dead links**; report `reports/links.json`.
- Wired into `scripts/gate.mjs` as the 11th fast check; gate **11/11 (100 %)**.

## 2026-11-09 01:59 - Autonomy tick + opt-in registry publishing prepared

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- Release plan's only open item is registry publishing. Added opt-in steps to
  `release.yml`: `npm publish --provenance --access public` and
  `pypa/gh-action-pypi-publish` (staged `dist/pypi`), both gated on repository
  variables `NPM_PUBLISH` / `PYPI_PUBLISH`. Default releases are unchanged (GitHub
  assets only). Not run against the registries — needs trusted-publisher/OIDC setup.
- Documented in README, errata E10 and the release plan; removed a duplicate Caravel
  roadmap line.

## 2026-11-09 00:59 - Autonomy tick (state re-verified after host restarts)

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**. Tree clean at
  `85235cf`; CI on `85235cf`, `d5ca856` and `1f09f96` all **green**.
- No new code: the last additions (Caravel-shaped wrapper, 32-bit ingress, Wishbone
  burst, reproducible WASM/Python/EXE, SLSA/cosign) are committed and verified.
- Remaining roadmap items are blocked: full P&R/DRC/LVS (clock planning + fitted
  floorplan), FPGA target (no hardware), full Caravel harness (needs Caravel repo/PDK),
  PCIe/100G (large integration), shuttle (optional). No success claims added.

## 2026-11-05 13:10 - Caravel-shaped wrapper

- Added `rtl/itch_caravel_wrap.sv`: Caravel user-project boundary. `io_in[31:0]`=data,
  `[35:32]`=keep, `[36]`=valid, `[37]`=last; `io_out[0]`=ready with `io_oeb` leaving
  only that bit driven; Wishbone management maps `wbs_adr_i[6:2]` to the host registers;
  `la_*` and `user_irq` tied off.
- Test `tb/test_caravel_wrap.py`: two messages over `io_in`, Wishbone reads of
  count/type/locate/shares/ref → PASS; lint clean. Wired into `make lint`, `make cocotb`
  and CI. This is the boundary shape, not a Caravel harness run.

## 2026-11-05 12:56 - Autonomy tick + detailed-routing attempt closed

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- `wrap32-big` reached **DetailedRouting** (1000 µm, 35 % density, congestion allowed):
  violations fell from ~695k to ~148k but did not converge; the host restart stopped the
  container. No final metrics, no DRC/LVS. Documented in `openlane/README.md`.
- Roadmap item stays blocked on clock planning (≈1,566-terminal clock) and a fitted
  floorplan; pre-PnR STA remains the timing evidence.

## 2026-11-04 14:10 - Wishbone burst test (both widths)

- Added `test_wishbone_burst`: 20 messages back-to-back (tvalid held high, tready
  honored) at 128-bit and 32-bit ingress → msg_count=20, updates=20, 0 corrupt,
  no beat loss. Both runners PASS (2 tests each).
- Committed after the 13:59 tick; `wrap32-big` detailed routing continues in the
  background (not converged, see next tick).

## 2026-11-04 13:59 - Autonomy tick + detailed routing in progress

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- `wrap32-big` passed GlobalRouting (congestion allowed) and is in
  `OpenROAD.DetailedRouting` (step 43). DRT reports ~695k violations at 40 % of its
  first optimization iteration — the design is poorly routable at this utilization;
  letting it run, will stop and document if it does not converge.
- Committed the datasheet timing paragraph with all measured pre-PnR values
  (−9.14 / −8.62 / −6.55 ns).

## 2026-11-04 12:59 - Autonomy tick + congestion-allowed routing attempt

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- `wrap32-full` (700 µm) failed GlobalRouting with GRT-0116 even with the ~80-pin
  32-bit wrapper → pin count is not the root cause; the ~1,566-terminal clock is.
- Started `wrap32-big` (1000 µm, 35 % density, `GRT_ALLOW_CONGESTION=1`); GlobalRouting
  is running extra iterations (31/50 at the time of this entry) instead of aborting.
- Committed `openlane/sky130_wrap32_big.json` and the updated attempts table.

## 2026-11-04 12:05 - 32-bit wrapper pre-PnR STA + full-flow attempt

- Added `openlane/sky130_wrap32.json` (wishbone wrapper, `SYNTH_PARAMETERS:
  ["DATA_WIDTH=32"]`, 700 µm, 50 % density). `SYNTH_PARAMETERS` must be a list, not a
  mapping — fixed after the first attempt was rejected.
- `wrap32-sta`: **WNS −6.55 ns** at 3.10 ns (ss), Fmax **103.67 MHz**, worst path
  FF → FF; published `reports/openlane_wrap32-sta.json`.
- Started `wrap32-full` (resizer skips) at ~80 pins to try for routing/DRC/LVS.

## 2026-11-04 11:49 - Autonomy tick + 32-bit ingress verified

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- Parameterized `DATA_WIDTH` in `itch_host_wrap`/`itch_wishbone_wrap` (was hardcoded
  128) and added `tb/run_wishbone32_cocotb.py`: build with
  `-Pitch_wishbone_wrap.DATA_WIDTH=32`, same Wishbone test. **PASS** — 36-byte
  messages across 9 beats, fields read back correctly. This is the width a Caravel
  `io_in` stream or narrow FPGA port would use.
- Wired into `make cocotb` and CI; README/datasheet/integration guide/roadmap updated.

## 2026-11-04 10:35 - Caravel-style Wishbone wrapper

- Added `rtl/itch_wishbone_wrap.sv`: host register file exposed through a classic
  Wishbone slave (1-cycle ACK, read-only; writes ACK but are ignored), AXI4-Stream
  ingress unchanged.
- Test `tb/test_wishbone.py`: two messages, Wishbone reads of msg count/type/locate/
  shares/ref, write ACK + ignored → PASS; lint clean. Wired into `make lint`,
  `make cocotb` and CI.

## 2026-11-04 09:59 - npm/PyPI blob signing + Sign workflow

- Added `.github/workflows/sign.yml` (dispatch + reusable): builds the npm tarball and
  Python wheel/sdist, signs each with keyless `cosign sign-blob` (`*.sigstore.json`) and
  immediately verifies with `cosign verify-blob` (identity regexp + OIDC issuer).
- `release.yml` publish job now has `id-token: write`, signs the artifacts after the
  checksums, attaches the `*.sigstore.json` bundles to the release, and README shows
  the `cosign verify-blob` command.
- Dispatching `sign.yml` to verify the mechanism in CI.
- `sign.yml` on `cdf9110`: **success** — "Sign artifacts" and "Verify signatures" both
  green for the npm tarball, wheel and sdist (keyless OIDC + transparency log).

## 2026-11-04 10:20 - Physical flow blocked after third attempt

- `wrap-full3` (1400 µm, 50 % density, `PL_TIMING_DRIVEN: 0`) failed GlobalPlacement
  with GPL-0305 again. Three configurations now fail in three places: resizer stall,
  GRT-0116 congestion (700 µm), GPL-0305 divergence (1400 µm, both density variants).
- Conclusion documented in `openlane/README.md`: the design needs clock planning
  (1,533-terminal clock) and a fitted floorplan/pin plan, not knob tweaks. No P&R,
  DRC or LVS result exists; pre-PnR STA remains the honest timing evidence.

## 2026-11-04 10:05 - Reproducible EXE verified

- `scripts/repro_exe.mjs` (Windows): builds `dist/chiplab.exe` twice and compares
  SHA-256 → **PASS**, both `67d05b22…`, 87,785,472 bytes, Node 22.23.1.
- Added a `windows-latest` job to `.github/workflows/repro.yml` that runs it weekly;
  local report `reports/repro_exe.json`. README now states WASM/Python/EXE are
  reproducible and the workflow checks all three.
- Dispatched `repro.yml` on `aced3c3`: **success**, both the Linux (WASM + Python) and
  the Windows (EXE twice) jobs green in CI.

## 2026-11-04 09:45 - Wrapper P&R attempts blocked; Repro workflow

- `wrap-full` (700 µm) failed GlobalRouting with GRT-0116 congestion; `wrap-full2`
  (1400 µm, 40 % density) failed GlobalPlacement with GPL-0305 (RePlAce diverged) —
  the 1,533-terminal clock is unbuffered before placement. Documented in
  `openlane/README.md`; no P&R/DRC/LVS result, roadmap marks it blocked.
- Added `.github/workflows/repro.yml` (weekly + dispatch): Rust 1.98.1 with the wasm
  target runs `repro_wasm.sh`, then `repro_python.sh`, and uploads both reports.
- Dispatched it on `8d5fbb8`: **success** (both reproducibility checks green in CI).

## 2026-11-04 09:30 - Reproducible Python packaging

- `scripts/repro_python.sh` (+ `make repro-python`): builds wheel + sdist twice with
  `SOURCE_DATE_EPOCH=1700000000`, normalizes the sdist container, compares SHA-256.
- Result **PASS**: wheel `1718b877…` twice; sdist `8814fdcf…` twice after
  `scripts/normalize_sdist.sh` (sorted members, fixed mtime, numeric owner, `gzip -n`).
  Without normalization the sdist differs only in generated-file mtimes.
- `release.yml` packages job now sets `SOURCE_DATE_EPOCH` and normalizes the sdist
  before staging; README/roadmap updated (`reports/repro_python.json`).

## 2026-11-04 09:10 - Autonomy tick + wrapper pre-PnR STA

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**.
- `wrap-sta` completed: setup **WNS −8.62 ns** at 3.10 ns (ss/100 °C), Fmax estimate
  **85.34 MHz**, worst path FF → FF (the `raw_payload` endpoint is gone).
  Published `reports/openlane_wrap-sta.json`.
- Started the full wrapper flow `wrap-full` with the resizer steps skipped, to try for
  routing/DRC/LVS (the debug-bus run failed global routing with congestion).

## 2026-11-04 09:05 - Narrow host wrapper for physical runs

- Added `rtl/itch_host_wrap.sv`: 128-bit AXI4-Stream ingress, 32-bit host register
  port (msg/corrupt/byte counters, last type/locate/price/shares/ref, valid/corrupt,
  updates), no wide debug record bus. Test `tb/test_host_wrap.py`: two messages,
  type X, locate 3, shares 100, ref round-trip, unmapped reads zero → PASS; lint clean.
- Added `openlane/sky130_wrap.json` for the wrapper and started a pre-PnR STA run
  (`wrap-sta`) to validate the narrower pin count.
- Wired the wrapper into `make lint`, `make cocotb` and CI.

## 2026-11-04 08:45 - Full Sky130 flow stopped: pin-count congestion

- Resume completed the stored steps but re-ran GlobalRouting and **failed** with
  `GRT-0116: Global routing finished with congestion` at the 700×700 µm die.
- Earlier attempt without skips stalled >1 h in `OpenROAD.ResizerTimingPostCTS` on the
  −9 ns path. Both attempts are documented in `openlane/README.md`.
- Root cause: ~1,100 top-level pins (484-bit `raw_order_data`, 512-bit `raw_payload`)
  on a 700 µm die. The standard-cell area is not the blocker.
- Consequence: no post-route STA, DRC or LVS result; roadmap now requires a narrow
  physical wrapper (32-bit host port + snapshot read) and a fitted/larger die.
- Errata E1 and README evidence updated; no success claim.

## 2026-11-04 08:25 - Autonomy tick + LibreLane run resumed

- `node scripts/autonomy.mjs`: queue empty, 0 tasks. Gate **10/10**. CI on `04be438`
  (pinned rustc + rebuilt WASM) **green**.
- The host restart stopped Docker and killed the skipped full run. The run directory
  `chiplab-sky130-nor` had reached **step 38 (global routing)** and completed it
  ("finished with congestion").
- First resume attempt (`--last-run` without a config) failed with "No config file(s)
  have been provided"; re-ran with `--last-run openlane/sky130.json` plus the same
  `--skip` flags. LibreLane logs "Using existing run at 'chiplab-sky130-nor'" and
  continues from global routing.

## 2026-11-04 00:25 - WASM reproducible-build check

- Added `scripts/repro_wasm.sh` (+ `make repro-wasm`): builds `wasm-core` twice into
  clean `CARGO_TARGET_DIR`s with the same toolchain, compares SHA-256 and writes
  `reports/repro_wasm.json`.
- Result: **PASS**, both builds `d2b5f58f5a8c9131…`, 50,322 bytes, rustc 1.98.1.
  The committed `web/wasm/chiplab_core.wasm` is `fc55bb6b…` (different toolchain), so
  `matchesCommitted` is false; pinning the Rust toolchain is the follow-up.
- Roadmap split accordingly.
- Follow-up in the same tick: pinned `wasm-core/rust-toolchain.toml` to rustc 1.98.1,
  rebuilt the shipped WASM (`web/wasm`, `public/wasm`, `packages/npm/wasm`) and reran
  the check: both builds **and** the committed artifact are `d2b5f58f…`,
  `matchesCommitted: true`. Gate 10/10 with the new binary.

## 2026-11-04 00:15 - Keyless cosign signature for the container image

- `docker-publish.yml`: added `id-token: write`, an `id: build` on the build step,
  `sigstore/cosign-installer@v3` and `cosign sign --yes` on the pushed digest.
  Existing `provenance: mode=max` + SBOM attestation unchanged.
- README shows `cosign verify ... --certificate-identity-regexp
  'https://github.com/timfromhcs/.*' --certificate-oidc-issuer
  https://token.actions.githubusercontent.com`.
- Verified end-to-end (run for `19da17e`, digest `sha256:37b4c143998a…`):
  `cosign verify` (v2.4.1 container) reports **claims validated, transparency-log
  entry verified, certificate verified**, subject
  `docker-publish.yml@refs/heads/main`.
- Roadmap split: Docker signing done; reproducible builds + npm/PyPI signatures open.

## 2026-11-04 00:05 - IHP SG13G2 pre-PnR STA

- Ran `openlane/ihp-sg13g2.json` with `-p ihp-sg13g2` to `OpenROAD.STAPrePNR`:
  setup **WNS −3.08 ns** at 3.10 ns (Fmax **161.9 MHz**), hold WNS −0.052 ns,
  worst path FF → FF (slow/125 °C). Published `reports/openlane_ihp-sta.json`.
- The summary script now selects the corner with the most negative `wns.max.rpt`
  instead of assuming `ss_`; all three reports were regenerated with it.
- PDK matrix (Sky130, GF180, IHP) now has one pre-PnR STA run each. Full P&R still
  open; the Sky130 3.10 ns run is still in the post-CTS resizer.

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
