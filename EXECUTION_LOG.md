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
