# AUTONOMOUS PLAN V2 — ChipLab: browser-first silicon lab, native runner, MCP/API, Vercel + EXE + Docker

> **Status: ACTIVE**
> Supersedes `AUTONOMOUS_PLAN.md` (V1). V1 remains as the first-iteration record.
> Owner: OpenCode Chief Engineering Agent
> Repo: `timfromhcs/ultra-low-latency-nasdaq-itch50-core`
> Host: Windows 11, Ryzen 7 7735HS, 24 GB DDR5, Radeon 680M (Vulkan 1.3), Node 22.23, Rust 1.96, WSL Ubuntu, Docker 29.6
> Started: 2026-11-03
> Rule: **no claim without a command**. Marketing numbers are either reproducible or labelled *illustrative*.
>
> **Progress snapshot (2026-11-03):** P0 complete except multi-frame Mold backpressure;
> P1 web/WebGPU complete; P2 backend/MCP complete; P3 packages complete; P4 EXE/Docker/
> Vercel build complete (no preview deploy); P5 native Vulkan + boost complete; P6 formal
> matrix + synthesis complete, OpenLane P&R open; P7 heartbeat registered; P8 docs/guides/
> README complete. See `EXECUTION_LOG.md` for commands and evidence.

---

## 0. What changed since V1

V1 delivered the first honest baseline and a large part of the RTL/verification repair:

- Verilator lint now passes (V1 failed on `EOFNEWLINE`).
- `itch_shifter.sv` rewritten with `tkeep`, cleared append window, parameterised width.
- `itch_parser_core.sv` decodes **all 22 ITCH opcodes**, preserves the full payload, extends shares to 64 bit.
- 100,000-message **full-field** regression against an independent Python model: **0 mismatches**, 3.14 MB, 41.29 Gbps model, byte conservation exact.
- Rust → `wasm32-unknown-unknown` core (`wasm-core/`) with the same parser, generator, chip models and top-of-book builder.
- Node backend (`backend/server.mjs`) + CLI (`backend/run.mjs`) + 8-chip compare (`lossy` correctly fails).
- WebAssembly ↔ Python cross-check: 10,000 records, 0 mismatches.
- MoldUDP64 front-end + depacketizer added; single-frame end-to-end test passes; **multi-frame backpressure is still open** (see risk R1).
- `web/wasm/chiplab_core.wasm` (~50 KB) built.

V2 now adds the **product surface**: browser demo with WebGPU, mobile-first UI, persistence, MCP, HTTP API, npm/PyPI packages, single EXE, Docker/GHCR, Vercel, native Vulkan, solver matrix, guides, SEO, and the hourly autonomy heartbeat.

---

## 1. Research: what is possible, and what we will actually build

### 1.1 Browser runtime

| Topic | Finding | Decision |
|---|---|---|
| WebAssembly | WASM is the only portable, near-native, sandboxed runtime that runs the same artifact in Chrome/Edge, Node, and a single EXE. | WASM core is the source of truth for the demo, backend, MCP and packages. |
| WebGPU | Chrome/Edge 113+; compute shaders with storage buffers; requires secure context (`localhost` is secure). | Use WebGPU for order-book binning + latency histograms; **Canvas2D fallback** for phones/older browsers. |
| Web Workers | Keep UI at 60 fps; run parsing/generation off the main thread. | Worker owns WASM memory; main thread only renders. |
| Persistence | OPFS is a real per-origin file system (Chrome 2023+); IndexedDB is universal; `navigator.storage.persist()` asks for durable storage. No server needed. | Store runs, settings and the last 5 result sets in **OPFS + IndexedDB fallback**; never send data to a cloud. |
| Offline | Service worker + cached WASM/JS/CSS. | PWA installable; demo works offline after first load. |
| Web container | container2wasm/WASI can run containers in the browser, but a full Linux container is overkill (tens of MB, slow). | Implement a **chip container runtime**: each chip is a sandboxed WASM module + manifest + resource limits, loaded/unloaded in a Worker. This is "Docker for chip models" without the VM weight. |
| Mobile | Responsive layout, touch targets ≥44 px, no hover-only controls, <150 KB JS gzip target. | 390 px and 1440 px gates; bottom sheet on mobile. |

### 1.2 Backend / deployment

| Option | Finding | Decision |
|---|---|---|
| Local Node backend | Same WASM, no deps, serves static + `/api/*`. | Primary developer path (`node backend/server.mjs`). |
| Vercel | Static output + serverless functions. Serverless functions are stateless; per-user data must be client-side (OPFS) or external storage. Vercel Sandbox Drives are persistent server-side storage but cost money and are not local. | Ship **static-first Vercel** (`public/` + `api/`) with client-side persistence. Optional Sandbox/Drives recipe documented for teams that want cloud persistence. |
| Docker | Node 22 alpine image, one command. GHCR prebuilt images via Actions. | `Dockerfile`, `docker-compose.yml`, GHCR workflow, local build + smoke test. |
| Single EXE | Node SEA (Node 22: `--experimental-sea-config` + postject) can embed one JS blob. Rust + embedded assets is an alternative. | Build `dist/chiplab.exe` with Node SEA, embedding web assets + WASM as base64. Fallback: Rust `include_dir` binary if SEA/publish fails. |
| npm package | Publish `@chiplab/core` with WASM + JS decoder + CLI. | `packages/npm/`, `npm pack` + local install test. |
| PyPI package | Publish `chiplab-itch` with the Python model + CLI. | `packages/python/`, `python -m build`, local wheel install test. |
| MCP | Model Context Protocol over stdio JSON-RPC; tools: chips, run, compare, book, formal_status. | `mcp/server.mjs`, no SDK dependency, test with a minimal client. |
| API | REST/JSON over the same core. | `/api/health`, `/api/chips`, `/api/run`, `/api/compare`, `/api/book`. |
| Vercel app on phone | Static site + PWA; WebGPU may be unavailable on some mobile browsers. | Auto-detect WebGPU; Canvas2D/WASM-only mode; no precision loss in the parser, only in visual aggregation (lower-resolution bins). |

### 1.3 Native / hardware

| Topic | Finding | Decision |
|---|---|---|
| Vulkan on 680M | Vulkan 1.3 compute is available; WebGPU uses it under the hood in Chrome. | Native `wgpu` runner with a compute shader; adapter info in `/api/health` and EXE `--probe`. |
| CPU boost | Windows power plans + process priority + affinity can be set per process; a GPU-present check can trigger it. | `--boost` on the native runner and `scripts/boost.ps1`: detect GPU via WMI, set `HIGH_PRIORITY_CLASS`, optionally pin to performance cores, restore on exit. **Opt-in**, never silent. |
| Precision | WebGPU `f32` is enough for price bins (prices are integers); parser stays integer-exact. | Integer parsing; f32 only for visual bin heights. "Low precision" mode uses fewer bins, not lossy parsing. |
| SAT/SMT solvers | Z3, CVC5, Boolector, Bitwuzla, Yices all speak SMT-LIB; SymbiYosys selects with `-s`. | `formal/solver_matrix.sh` + CI matrix; record version/time/result. |

### 1.4 Verification and evidence

- **Field-level** Python model (already 100k/0 mismatches).
- **Formal**: BMC + k-induction + covers on the new interface; separate shifter invariants.
- **Mutation**: ≥10 RTL mutants, all killed.
- **Synthesis matrix**: Yosys for 128/256/512; OpenLane configs for Sky130/GF180/IHP.
- **Browser gates**: Playwright at 390/1440, console errors = 0, WebGPU adapter or fallback, screenshot artifact.
- **Honesty**: README labels pre-silicon, no "silicon-proven", no "0-cycle from wire" (true latency is 2 clocks wire-to-register).

---

## 2. Product definition

**ChipLab** is a local-first market-data silicon lab:

1. Open the web app (localhost, Vercel, or `chiplab.exe`).
2. Pick a chip (RTL twin, 2-cycle safe, 512-bit, Mold front-end, order-book, rivals, lossy negative control).
3. Generate 1k–2M ITCH messages (raw, MoldUDP64, Ethernet).
4. Run in a sandboxed WASM "container" in a Worker.
5. See live order book, tape, latency histogram and throughput.
6. Compare all chips against the golden model; `lossy` must fail.
7. Everything works offline; results persist locally in OPFS.
8. The same core is available as npm, PyPI, MCP, REST, Docker and a single EXE.

**Non-goals:** cloud multi-tenant SaaS, real trading, tapeout claims.

---

## 3. Target architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Web UI (responsive PWA)                                             │
│  ├─ main.js  (DOM, charts, controls)                                │
│  ├─ worker.js (WASM chip container, OPFS/IndexedDB)                 │
│  ├─ gpu.js   (WebGPU compute: bins/histograms; Canvas2D fallback)   │
│  └─ service-worker.js (offline cache)                               │
└───────────────┬─────────────────────────────────────────────────────┘
                │ same wasm
┌───────────────▼───────────────┐   ┌───────────────────────────────┐
│ Node local backend            │   │ Vercel static + api/          │
│  /api/*, static, MCP stdio    │   │  same JSON contract           │
└───────────────┬───────────────┘   └───────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────────────┐
│ chiplab_core.wasm (Rust)                                            │
│  parse | generate | run_chip | compare | build_book | version       │
└───────────────┬─────────────────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────────────┐
│ RTL v2 (SystemVerilog)                                              │
│  itch_shifter → itch_parser_core → itch_top                         │
│  moldudp64_frontend → depacketizer → pipeline                       │
│  variants: 128 / 256 / 512 / mold / book                            │
└─────────────────────────────────────────────────────────────────────┘

Native: wgpu Vulkan compute (order-book bins, histogram) + optional boost
Packages: @chiplab/core (npm) · chiplab-itch (PyPI) · ghcr.io/.../chiplab
```

---

## 4. Phases, tasks, acceptance criteria

### P0 — Stabilise the V1 work (blocking)
- [x] Lint clean, 100k full-field RTL regression, WASM/Python cross-check.
- [ ] Fix the multi-frame Mold pipeline backpressure (or mark the full pipeline experimental and keep the single-frame proof).
- [ ] Update standalone `tb/test_mold.py` for the new ports (`frame_busy`, `m_axis_tready`).
- [ ] Formal harness migration to the v2 interface (shares 64, payload, tkeep).
- [ ] Makefile: `verify-fast`, `verify-deep`, `verify` with no Bash-only hidden state.
- [ ] `reports/` schema + `scripts/gate.mjs`.

**Acceptance:** `make verify-fast` green; deep run green; no stale/broken test.

### P1 — Web app (the centrepiece)
- [ ] `web/index.html`, `styles.css`, `app.js`, `worker.js`, `gpu.js`, `pwa.js`.
- [ ] SOTA dark lab UI: 8 px grid, accessible contrast, keyboard shortcuts, reduced motion.
- [ ] Responsive: 390 px (bottom nav, stacked cards), 768 px, 1440 px (3-column).
- [ ] WebGPU compute shader: price bins + latency histogram; render bars/heatmap.
- [ ] Canvas2D fallback; no WebGPU → still fully functional.
- [ ] Worker runs WASM; main thread never blocks >16 ms.
- [ ] Persistence: OPFS + IndexedDB fallback; save/restore last runs/settings; "clear data".
- [ ] PWA: installable, offline cache, `manifest.webmanifest`, icons.
- [ ] Chip container UI: list, load/unload, resource badge, "sandbox" indicator.
- [ ] Live mode: generate → parse → book → render at 60 fps; pause/step/reset.
- [ ] Comparison table + Pareto chart; lossy chip red status.
- [ ] Mobile: no hover-only controls, 44 px targets, screen-size aware chart density.
- [ ] Playwright gates at 390/1440; screenshots; console error = 0.
- [ ] Better Design review pass (`get-ui-principle`, `get-ux-principle`, `review-ui-code`).

**Acceptance:** `node backend/server.mjs` → open app, run 1M, see book/histogram; `--disable-gpu` still works; mobile viewport passes.

### P2 — Local backend, MCP, API
- [ ] `/api/health`, `/api/chips`, `/api/run`, `/api/compare`, `/api/book`, `/api/export`.
- [ ] Request validation, limits, no path traversal, no secrets, CORS local.
- [ ] MCP stdio server: `initialize`, `tools/list`, `tools/call` (`chiplab.chips`, `chiplab.run`, `chiplab.compare`, `chiplab.book`, `chiplab.formal_status`).
- [ ] MCP client smoke test.
- [ ] OpenAPI-ish `docs/api.md`.
- [ ] Native `--probe` reports Vulkan adapter, CPU, memory.

**Acceptance:** `node mcp/server.mjs` handshake + tools work; `curl` examples return valid JSON; `node backend/run.mjs --compare` prints table.

### P3 — Packages
- [ ] `packages/npm/`: `@chiplab/core`, WASM + `index.mjs`, types, CLI; `npm pack`; local install test.
- [ ] `packages/python/`: `chiplab-itch`, model + CLI; `pyproject.toml`; `python -m build`; wheel install test.
- [ ] Versioning (`0.2.0`), README per package, licence/attribution.
- [ ] Publish scripts (require `NPM_TOKEN` / `PYPI_TOKEN`); CI dry-run.
- [ ] `npm pack --dry-run`, `twine check` equivalent.

**Acceptance:** package tarball/wheel installs in a clean temp dir and parses a known vector.

### P4 — Single EXE, Docker, Vercel
- [ ] `scripts/build_exe.mjs`: inline assets, Node SEA blob, postject; `dist/chiplab.exe`.
- [ ] EXE serves web + API, opens browser, `--port`, `--no-open`, `--probe`.
- [ ] `Dockerfile` multi-stage, non-root, healthcheck; `docker-compose.yml`.
- [ ] `docker build` + `docker run` smoke test.
- [ ] GHCR workflow (build only; push on tag with `GITHUB_TOKEN`).
- [ ] `vercel.json`, `api/*.mjs`, `scripts/build_vercel.mjs` (copy web → public, inline wasm path).
- [ ] `vercel build`/`vercel deploy` dry run; deploy only if authenticated and user approves.
- [ ] Phone test: open Vercel URL, responsive, fallback mode.

**Acceptance:** `dist/chiplab.exe` runs standalone; `docker run` serves; `vercel build` succeeds; no cloud persistence of user data.

### P5 — Native Vulkan + boost
- [ ] `native/` Rust `wgpu` compute runner: adapter probe, order-book bins, latency histogram.
- [ ] WGSL shader shared conceptually with WebGPU.
- [ ] `--boost` (opt-in) sets Windows priority; `--affinity` pins to first N physical cores; restore on exit.
- [ ] `scripts/boost.ps1` detects GPU (WMI), prints plan, applies with `-Apply`.
- [ ] Fallback if no Vulkan adapter: CPU path, clear message.
- [ ] Benchmark CPU vs GPU bins for 1M records; report honest speedup/latency.

**Acceptance:** native binary prints `Radeon 680M` and produces the same bins as the WASM/JS reference.

### P6 — Formal, SAT matrix, synthesis
- [ ] Rewrite `formal/itch_formal.sv` for v2; add shifter invariants.
- [ ] `formal/solver_matrix.sh`: z3, cvc5, boolector, bitwuzla/yices if present; record version/time/result.
- [ ] BMC + k-induction + cover on all solvers that support the features.
- [ ] Mutation testing ≥10 mutants, all killed.
- [ ] `synth/synth_matrix.py` for 128/256/512; `reports/synth_*.json`.
- [ ] OpenLane configs: sky130, gf180, ihp-sg13g2; label "flow-ready, not P&R-signed".
- [ ] Replace hand-drawn layout claim with "illustrative floorplan" or actual run.

**Acceptance:** formal PASS on ≥2 independent solvers; mutation score ≥90%; synth reports committed.

### P7 — Autonomy, heartbeat, RSI
- [ ] `scripts/heartbeat.ps1` writes `reports/heartbeat.log`.
- [ ] `scripts/register_heartbeat.ps1` registers a Windows Scheduled Task every hour.
- [ ] Task invokes `opencode run --continue --auto --prompt "Hallo, es ist <time>. Autonomy tick: ..."` with project cwd; logs to `reports/heartbeat.log`.
- [ ] `scripts/autonomy.mjs`: queue-based next-task runner; reads `autonomy/queue.json`, runs gates, updates `EXECUTION_LOG.md`.
- [ ] Document the honest limitation: a scheduled task cannot guarantee that this exact chat window is focused; it will resume the newest session in this project.
- [ ] `EXECUTION_LOG.md` append-only; `reports/scorecard.json`.

**Acceptance:** task exists (`schtasks /query`), a manual tick appends a log line; disabling works (`Unregister-ScheduledTask`).

### P8 — Docs, SEO, honesty, release
- [ ] Rewrite `README.md` with: what it is, what it is not, architecture, quickstart (web/EXE/Docker/Vercel/npm/PyPI/MCP), evidence table, limitations, roadmap, licence.
- [ ] `docs/guides/en/zero-to-hero.md`, `de/`, `fr/`.
- [ ] `docs/architecture.md`, `docs/benchmarks.md` regenerated from reports.
- [ ] `llms.txt`, `llms-full.txt`, JSON-LD, `robots.txt`, `sitemap.xml`, OpenGraph SVG.
- [ ] `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, third-party notices.
- [ ] CI: RTL, formal, wasm, backend, web, packages, docker build, docs links.
- [ ] `git diff --check`; merge to `main`; tag `v0.2.0`; push (only with user auth).
- [ ] Screenshot/GIF artifact for the README.

**Acceptance:** fresh clone → `make verify` or documented Docker one-liner; README numbers trace to `reports/`; all guides build.

---

## 5. Definition of Done (V2)

- [ ] `make verify` green: lint, 100k RTL full-field, formal (≥2 solvers), mutation, WASM cross-check, backend, MCP, packages.
- [ ] Web demo works on desktop and 390 px mobile; WebGPU path + Canvas2D fallback; offline; OPFS persistence.
- [ ] `chiplab.exe` (single file) and `docker run` both serve the same demo.
- [ ] `vercel build` produces a deployable static+API bundle; optional preview deploy.
- [ ] MCP tools usable from an MCP client.
- [ ] npm + PyPI artifacts install in clean dirs.
- [ ] Native Vulkan probe finds the 680M; `--boost` is opt-in and reversible.
- [ ] Heartbeat task registered; logs prove ticks.
- [ ] README/guides honest, SEO-complete, EN/DE/FR.
- [ ] `main` updated, `v0.2.0` tag, no uncommitted noise.

---

## 6. Self-healing / autonomy loop

```text
every tick (manual or hourly):
  1. read autonomy/queue.json → next task
  2. run the narrow gate for that task
  3. on failure: classify (rtl | wasm | web | backend | mcp | pkg | exe | docker | docs)
     - collect the exact command + first error
     - apply the smallest diff
     - rerun only that gate (max 3 attempts)
  4. on success: mark done, append EXECUTION_LOG.md, update scorecard
  5. if all gates green: run verify-deep, write release candidate
  6. never weaken a test; add a regression first
  7. never claim a number without a report
```

**Escalation:** two failures in the same gate → stop and write a root-cause note. Any public-interface change updates `docs/architecture.md` and `llms-full.txt` in the same commit.

**Tool map**

| Need | Tool |
|---|---|
| HDL | WSL: Verilator 5.032, Yosys 0.52, Icarus 12, Z3, CVC5, Boolector |
| WASM | Rust 1.96 `wasm32-unknown-unknown` |
| Backend/MCP/EXE | Node 22 SEA, postject |
| Browser | Playwright / Chrome DevTools MCP |
| Design | Better Design MCP |
| Review | subagents `qa-tester`, `security-auditor`, `ui-ux-specialist`, `ast-refactor-pro` |
| Native | Rust `wgpu` + Windows priority APIs |
| Deploy | Docker, GHCR, Vercel MCP/CLI |
| Memory | `EXECUTION_LOG.md`, `reports/`, Basic Memory (optional) |

---

## 7. Risk register

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| R1 | Mold multi-frame backpressure race | High | Keep one-frame proof; add proper AXI-Stream skid/FIFO; label pipeline experimental until green |
| R2 | Node SEA/postject unavailable or blocked | Medium | Fallback: Rust `include_dir` binary; or portable folder + launcher |
| R3 | WebGPU unavailable on mobile/older GPU | High | Canvas2D + WASM-only mode; detect and label |
| R4 | Vercel serverless cannot ship 50 KB WASM + assets | Low | Static-first; API only for stateless compute; client persists |
| R5 | Native wgpu build heavy/fails | Medium | CPU fallback; keep WebGPU as primary; document |
| R6 | Solver package missing (bitwuzla/yices) | Medium | Probe and skip; require ≥2 solvers for claim |
| R7 | Hourly task does not surface in this exact chat | High | Document limitation; task resumes newest session; log ticks; manual `autonomy.mjs` always works |
| R8 | Scope explosion | High | Phase gates; ship P0–P4 first; P5–P7 best-effort with honest labels |
| R9 | Licence contamination | Low | PolyForm retained; third-party notices; no GPL code copied |

---

## 8. Execution log

See [`EXECUTION_LOG.md`](EXECUTION_LOG.md). Each tick records: timestamp, task id, command, result, next.
