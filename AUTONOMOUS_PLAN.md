# AUTONOMOUS PLAN — ChipLab / ITCH-50 Silicon Lab

> Status: **SUPERSEDED by [`AUTONOMOUS_PLAN_V2.md`](AUTONOMOUS_PLAN_V2.md)**
> The V1 analysis and gap matrix remain as the first-iteration record.
> Owner: OpenCode Chief Engineering Agent
> Repo: `timfromhcs/ultra-low-latency-nasdaq-itch50-core`
> Working copy: `E:\chips\main`
> Started: 2026-11-03
> Rule: every claim in this repo must be reproducible by a command, or it is labelled **illustrative**.

---

## 0. Mission

Turn the current single-module ITCH parser into a **local-first, verifiable market-data silicon lab**:

1. **Better chip** — correct framing, all ITCH fields, lossless reference data, `tkeep`/`tlast`, parameterised 128/256/512-bit datapath, honest timing.
2. **More chips** — a registry of RTL variants (bandwidth, latency/area trade-offs, MoldUDP64 front-end, order-book stage) that can be built and compared.
3. **More proofs** — full-field equivalence, framing/byte-conservation invariants, no-loss/no-duplication, plus mutation testing that proves the tests can fail.
4. **More ASIC targets** — Sky130, GF180, IHP SG13G2 OpenLane/LibreLane configs, a synthesis matrix, and reproducible area/Fmax reports.
5. **Local backend** — a Node service that runs the same WASM chip models as the browser, validates them against an independent golden model, and benchmarks "other chips" head-to-head.
6. **WebGPU + WebAssembly demo** — the whole lab runs on the user's own hardware in a browser (Chrome/Edge WebGPU), with a Canvas2D fallback; Docker image for one-command reproduction.
7. **Better README** — no invented numbers, a clear maturity label, quickstart, architecture, verification evidence, benchmark methodology, roadmap.

**Non-goal:** claiming a tapeout or silicon-proven status. This is pre-silicon RTL + an executable digital twin.

---

## 1. Baseline: what the other agent actually left behind

### 1.1 Verified facts (commands run 2026-11-03)

| Check | Result | Evidence |
|---|---|---|
| Git state | 2 commits, `main` clean | `git log --oneline` |
| Verilator lint | **FAILED before fix**: 5 × `EOFNEWLINE` warnings promoted to errors | `verilator --lint-only -Wall ...` |
| 1M packet sim | Build failed for the same reason; after newline fix it runs | `tb/Makefile` |
| Cocotb | **FAILED**: `ModuleNotFoundError: scapy`; only checks 5 of 17 outputs | `tb/test_itch.py` |
| Formal | Harness only proves "registered output equals delayed raw output" (tautology) + class exclusivity | `formal/itch_formal.sv` |
| Layout | `docs/generate_layout.py` draws boxes by hand; **not** OpenLane output | `scripts/render_gds.py` |
| Lint/toolchain | Not installed on Windows; WSL Ubuntu required | `which verilator yosys` |

### 1.2 Structural defects found by code review

| # | Severity | Defect | Impact |
|---|---|---|---|
| D1 | **Critical** | `itch_shifter.sv` ORs the new 128-bit word into the buffer at `post_consume_count` **without clearing the destination region**. Stale bytes survive and are OR-ed with new data. | Silent payload corruption whenever the buffer holds >16 bytes and a partial message is consumed. It only hides because the 1M generator mostly streams aligned traffic. |
| D2 | **Critical** | No `tkeep`. AXI4-Stream partial final beats are undefined; trailing pad bytes are parsed as messages. | Real MAC/DMA integration is broken; fuzz "passes" only because the harness pads with zeros and counts expected messages. |
| D3 | **Critical** | No Ethernet/IP/UDP/MoldUDP64 front-end and no sequence-gap detection. | Cannot attach to the actual NASDAQ feed; drops/losses are invisible. SOTA (NovaSparks/Fractal) parses L2–L4+Mold as bytes arrive. |
| D4 | **High** | `s_axis_tlast` is unused. | No packet boundary, no resync, no gap accounting. |
| D5 | **High** | Only 9 trading opcodes are decoded; the other 13 are zeroed and marked drop. Stock Directory (`R`) is thrown away, so `stock_locate → symbol` is lost. | Downstream cannot resolve symbols or trading state. Reference data is not "non-trade garbage". |
| D6 | **High** | The 1M test checks only type/locate/shares/price. Cocotb checks type/locate/is_trade/is_drop/corrupt. | "100% bit-exact" is not proven. Timestamp, ref numbers, stock, match, side, MPID are untested. |
| D7 | **High** | "0-cycle / 1.1 ns" bypass is measured from a **registered** buffer, not from `s_axis_tdata`. True wire-to-output is ≥2 cycles. The 452-bit mux + 1024-bit barrel shift will not close at 322 MHz in Sky130. | Misleading latency and timing claims. |
| D8 | **Medium** | `s_axis_tready` is high whenever `buf_count <= 112`; with 16 B/cycle in and ≤1 message/cycle out, a burst of 12–15 B messages can build occupancy until backpressure. | Throughput is message-rate-limited, not byte-rate-limited. Fine for ITCH, but must be documented. |
| D9 | **Medium** | `raw_stock_locate_pre_trigger` is valid even when `raw_order_valid=0`. | Downstream may prefetch garbage. |
| D10 | **Medium** | `openlane/config.json` uses a 450×450 µm die for 21k cells at 55% density; physically implausible for Sky130. | "Layout preview" is decorative. |
| D11 | **Medium** | `make verify_all` is Bash-only and depends on `.venv`, `/tmp`, `klayout`, `wavedrom`; CI installs only a subset. | CI is red or skipped; no Windows path. |
| D12 | **Low** | `tb/generate_pcaps.py` generates a MoldUDP64 header per UDP packet but always `msg_count=1`; the payload contains many ITCH messages. | PCAP is not a valid feed capture. |
| D13 | **Low** | README badges/claims (41.25 Gbps, 21,811 cells, 322 MHz, "silicon-proven") have no CI artifact or synthesis log. | Trust/SEO risk. |

---

## 2. SOTA research (what the best implementations do)

### 2.1 Latency & architecture

| Source | Claim / pattern | Lesson for us |
|---|---|---|
| Marc Battyani / Fractal Scientific, *sub-25 ns open-source NASDAQ ITCH FPGA parser* (2021, updated) | 8 cycles @ 322.265 MHz = **24.8 ns**, from last byte to decoded command; parses **Ethernet + IPv4 + UDP + MoldUDP64 + ITCH** as bytes arrive; outputs 297-bit canonical commands; filters by IP/UDP port. | Real latency is measured from a defined reference point (last byte / first byte) and includes L2–L4. We must publish a **latency budget with a reference point**, not a marketing "0 cycles". |
| NovaSparks (same author; first pure-FPGA feed handler, 2008) | Full feed handler: parser + order book + symbol mapping. | Parser alone is not a product; add reference data and a book stage. |
| Vitis HLS ITCH feed handler (2026) | 6-cycle **parse-to-book-insert** at 250 MHz = 24 ns. | The useful metric is parse-to-book, not parse alone. Add a book stage and measure it. |
| TechRxiv *Speculative, macro-driven FPGA architecture for ultra-low-latency ITCH* (2025) | Speculative/macro-driven parser, canonical output, one-cycle-class decode. | Speculation is valid, but must be paired with a framing/validity layer and formal proofs. |
| Columbia ELEN 4840 proposal (2026) | Parser + **sorted hardware order book**; compares FPGA vs ARM HPS; uses 2-byte length framing like MoldUDP64. | Include an order-book stage and a CPU baseline for honest comparison. |
| BRH *FPGA HFT Order Book* series (2026) | L2→UDP→Mold→ITCH pipelined parsers; `tlast` framing; sequence-gap detection; hash-table/XOR-folding order book, collision handling, synthesis. | `tlast`, gap detection, and order-book hashing are table stakes. |
| Enyx / AMD-Xilinx / NovaSparks commercial feed handlers | 3–8 cycle parse pipelines, 10/25/40/100G MAC integration, 100s of ns wire-to-wire. | Our "1 cycle" must be qualified: it excludes MAC, framing, CDC, and the book. |

### 2.2 Verification SOTA

- **Cocotb 2.x + Verilator 5** with real captured/generated packets, not just synthetic aligned streams.
- **Independent golden model** (C++/Python/Rust) compared field-by-field on **every** output, including negative cases.
- **Constrained-random + coverage closure**: all opcodes, all lengths, split/unaligned beats, `tkeep` partial beats, backpressure, reset during traffic, corrupt opcodes, duplicate/out-of-order sequence.
- **Formal**: SymbiYosys + Z3 for invariants; **mutation testing** to prove the assertions/tests are not vacuous.
- **Synthesis evidence**: Yosys/OpenROAD/OpenLane reports checked into `reports/`, with Fmax and cell area per target.

### 2.3 ASIC / FPGA flow SOTA

- **OpenLane 2 / LibreLane** flows for Sky130 and GF180; **IHP SG13G2** open PDK; Caravel-style harness for tapeout.
- Use `SYNTH_STRATEGY=DELAY`, `PL_TARGET_DENSITY` realistic (0.55–0.70), and report **slack**, not just cell count.
- For FPGA: UltraScale+ / Agilex, 322.265625 MHz is the standard 10G/25G line-rate clock; 512-bit @ 322 MHz = 165 Gbps theoretical.

### 2.4 Browser / local-first SOTA

- **WebAssembly** for the deterministic chip model (same artifact in Node and browser).
- **WebGPU compute** for parallel aggregation (price-level bins, latency histograms, book heatmaps); Canvas2D fallback.
- **container2wasm / Docker + WASM** pattern: package the lab as a static + Node image so the whole demo runs on the user's hardware, not a cloud VM.
- WebGPU requires a secure context (`https://` or `localhost`); Chrome 113+/Edge 113+.

**Sources:** Nasdaq TotalView-ITCH 5.0 spec; Fractal Scientific parser README; Hugo BRH MoldUDP64/ITCH series; Columbia 4840 proposal; Vitis HLS post; TechRxiv 2025; OpenLane/LibreLane docs; MDN WebGPU; container2wasm.

---

## 3. Gap matrix (current vs. target)

| Capability | Current | Target (this plan) | Priority |
|---|---|---|---|
| Byte-exact ITCH parse, all 22 opcodes | Partial (9 decoded, 13 zeroed) | All opcodes, all fields, payload preserved | P1 |
| AXI4-Stream correctness | No `tkeep`, no `tlast` | `tkeep`-aware, `tlast` framing, partial beats | P1 |
| Buffer integrity | Stale-byte OR bug | Cleared append window, formal byte conservation | P0 |
| Verification | Type/locate only | Full-field equivalence + mutation + corner cases | P1 |
| Formal | Tautological | Framing, no-loss, field slices, class exclusivity | P1 |
| MoldUDP64 / L2-L4 | None | Front-end filter + sequence gap detection | P2 |
| Reference data | Dropped | `R/H/Y/L/...` payload + symbol map | P2 |
| Bandwidth | 128-bit only | 128/256/512-bit variants | P2 |
| Order book | None | Top-of-book + depth bins (RTL and WASM) | P3 |
| ASIC targets | 1 decorative config | Sky130/GF180/IHP configs + synth matrix | P3 |
| Local backend | None | Node API, chip registry, compare endpoint | P4 |
| Browser demo | None | WebGPU + WASM, Canvas2D fallback, Docker | P5 |
| Docs | Marketing | Honest README + reproducible reports | P6 |

---

## 4. Target architecture

```
                         ┌──────────────────────────────────────────────┐
  Ethernet / PCIe / DMA  │  moldudp64_frontend.sv (P2)                  │
  AXI4-Stream 128/256/512│  - L2/L3/L4 filter, UDP port, Mold header    │
                         │  - session/seq, gap pulse, packet count      │
                         └──────────────────────┬───────────────────────┘
                                                │ ITCH byte stream (tkeep/tlast)
                         ┌──────────────────────▼───────────────────────┐
                         │  itch_shifter.sv (P0/P1)                      │
                         │  - cleared append window, tkeep, tlast        │
                         │  - 512-bit sliding window, 0 bubbles           │
                         └──────────────────────┬───────────────────────┘
                                                │
                         ┌──────────────────────▼───────────────────────┐
                         │  itch_parser_core.sv (P1)                     │
                         │  - all 22 opcodes, full field decode          │
                         │  - pre-trigger, drop/trade/ref classification │
                         │  - raw payload preserved                      │
                         └───────────┬──────────────────┬───────────────┘
                                     │                  │
                    ┌────────────────▼───────┐  ┌───────▼────────────────┐
                    │  Registered egress      │  │  itch_top_of_book.sv   │
                    │  1-cycle canonical rec  │  │  locate→BBO/volume     │
                    └─────────────────────────┘  └────────────────────────┘

  Offline twin (same semantics):
  Rust → wasm32  ──►  Node backend (compare/all chips)  ──►  WebGPU demo
```

**Chip variants (registry):**

| ID | What | Datapath | Latency model | Purpose |
|---|---|---|---|---|
| `rtl-1c` | Fixed RTL semantic twin | 128 | 1 cycle after buffer | Baseline |
| `rtl-2c-safe` | Registered, no async bypass | 128 | 2 cycles | Timing-closed variant |
| `rtl-512` | 512-bit variant | 512 | 1 cycle | 165 Gbps theoretical |
| `mold-128` | MoldUDP64 front-end + parser | 128 | 3 cycles | Full feed |
| `book-128` | Parser + top-of-book | 128 | 2 cycles | Parse-to-book |
| `scalar` | Golden software | — | n/a | Reference |
| `rival-3c` | Enyx-class model | 128 | 3 cycles | Comparison |
| `rival-2c` | NovaSparks-class model | 128 | 2 cycles | Comparison |
| `lossy` | Drops admin/ref data | 128 | 1 cycle | Negative control |

---

## 5. Phases, tasks, acceptance criteria

### P0 — Truth & baseline (blocking)
- [x] Install WSL toolchain: Verilator 5.032, Yosys 0.52, Icarus 12, Z3.
- [x] Run lint, 1M sim, cocotb, formal; capture real failures.
- [x] Fix EOF newline lint failures.
- [x] Write this plan + SOTA + gap docs.
- [ ] Add `scripts/bootstrap.sh` / `scripts/bootstrap.ps1` that installs the toolchain.
- [ ] Make `make lint` pass cleanly on a fresh clone.

**Acceptance:** `make lint` → 0; baseline test results documented in `EXECUTION_LOG.md`.

### P1 — Correctness hardening
- [ ] Rewrite `itch_shifter.sv`: cleared append window, `tkeep`, `tlast`, generic `DATA_WIDTH`, occupancy assertions.
- [ ] Rewrite `itch_parser_core.sv`: all 22 opcodes, full fields, preserve raw payload, valid pre-trigger.
- [ ] Update `itch_top.sv`: `s_axis_tkeep`, `m_payload`, `m_msg_len`, message/byte/error counters.
- [ ] Add `tb/reference_model.py`: independent, strict, all fields, truncation/resync.
- [ ] Add `tb/test_vectors.py` / JSON fixtures: all opcodes, all lengths, split beats, partial `tkeep`, corrupt/resync.
- [ ] Extend `tb/sim_main.cpp`: full-field comparison against canonical records; `--packets/--seed`; report JSON.
- [ ] Extend cocotb: full-field assertions + `tkeep` partial beats.
- [ ] Formal: `formal/itch_shifter_formal.sv` (byte conservation, no overflow, append position), `formal/itch_fields.sv` (field slices per opcode), keep the register-equivalence proof.
- [ ] Mutation testing: `tools/mutate.py` with ≥10 mutants; all must be killed.
- [ ] Cocotb/scapy dependency fixed; CI runs on Ubuntu with a lockfile.

**Acceptance:** 1M packets, all 17 record fields bit-exact vs. Python; 0 mismatches; ≥10/10 mutants killed; formal BMC+K-induction PASS; cocotb PASS.

### P2 — Bandwidth & protocol coverage
- [ ] Parameterise `DATA_WIDTH` 128/256/512; fix all hard-coded 16/64/512 widths.
- [ ] Add `rtl/moldudp64_frontend.sv`: Ethernet/IPv4/UDP filter (configurable IP/port), Mold header, `frame_ok`, `seq`, `msg_count`, `gap`, `drop`.
- [ ] Add reference-data decode: `R` symbol, `H` trading state, `Y` reg-SHO, `L` MPID position, `S/V/W/K/J/h/B/I/N` payloads.
- [ ] Add `tlast`-based resync and gap counters.
- [ ] Throughput proof: measure messages/cycle and bytes/cycle; document the 1-message/cycle limit.
- [ ] Add `chips/*.json` registry + generator script.

**Acceptance:** Mold packet stream with one dropped sequence → exactly one `gap` pulse, no misparse; 512-bit variant lints and simulates; `R` symbol reconstructs `AAPL    `.

### P3 — ASIC / FPGA targets
- [ ] `openlane/sky130.json`, `gf180.json`, `ihp-sg13g2.json` with realistic die/core area and clock.
- [ ] `synth/synth_matrix.py`: Yosys synth for 128/256/512, emit `reports/synth_<variant>.json` (cells, DFFs, area proxy).
- [ ] `scripts/fmax_probe.py`: run OpenSTA/OpenROAD if available; otherwise report "not run" honestly.
- [ ] Replace hand-drawn layout with a clearly labelled "illustrative floorplan" or an actual OpenLane render.
- [ ] `reports/` checked in (small JSON/markdown only).

**Acceptance:** every number in README links to a report; no unlabelled estimates.

### P4 — Local backend / chip lab
- [ ] `wasm-core/` Rust crate with `parse`, `generate`, `build_book`, `run_chip`, stats ABI.
- [ ] Build `web/wasm/chiplab_core.wasm` via `scripts/build_wasm.ps1` / `.sh`.
- [ ] `backend/server.mjs`: static server + `/api/health`, `/api/chips`, `/api/run`, `/api/compare`.
- [ ] Independent JS golden parser used by the backend to validate WASM output.
- [ ] `backend/run.mjs` CLI with JSON output.
- [ ] Chip registry with 9 models; `lossy` must fail correctness, `rival-*` must pass with different latency.

**Acceptance:** `node backend/run.mjs --compare --packets 200000` prints a table; golden vs. `rtl-1c` = 0 mismatches; `lossy` > 0; all 9 run.

### P5 — WebGPU / WebAssembly demo
- [ ] `web/index.html`, `styles.css`, `app.js` (no build step, ES modules).
- [ ] WebGPU compute: price-level binning + latency histogram; render bars/heatmap.
- [ ] Canvas2D fallback when `navigator.gpu` is absent.
- [ ] Live mode: generate → parse → aggregate → render at 60 fps; pause/step/reset.
- [ ] Chip comparison UI: table + Pareto (latency vs. throughput).
- [ ] Local backend toggle: run the same job via `/api/compare`.
- [ ] `Dockerfile` + `docker-compose.yml`; `make demo`.
- [ ] Playwright/Chrome check at 390 px and 1440 px; no console errors; WebGPU adapter reported.

**Acceptance:** open `http://localhost:8080`, run 1M messages, see live book/heatmap and latency; `docker compose up` works; fallback works with `--disable-gpu`.

### P6 — Docs & release
- [ ] Rewrite `README.md`: honest maturity, quickstart, architecture, evidence table, demo screenshots.
- [ ] `docs/architecture.md`, `docs/benchmarks.md` updated from reports.
- [ ] `llms.txt` / `llms-full.txt` updated.
- [ ] CI: lint + sim (small) + formal + pytest + wasm build + backend test + web smoke.
- [ ] `CHANGELOG.md`, `CONTRIBUTING.md`, issue templates (optional).
- [ ] Licence/attribution unchanged, add third-party notices.

**Acceptance:** fresh clone + `make verify` passes in CI; README numbers all traceable.

### P7 — Self-healing / RSI
- [ ] `scripts/self_heal.py`: run stages, parse JSON, classify failure, apply bounded retries, write `reports/self_heal.json`.
- [ ] `scripts/scorecard.py`: one score per stage (lint, sim, formal, mutation, wasm, ui).
- [ ] `EXECUTION_LOG.md` appended automatically.
- [ ] Optional: invoke local subagents (`qa-tester`, `security-auditor`, `ui-ux-specialist`, `ast-refactor-pro`) for review passes.

**Acceptance:** intentionally break a test → loop detects, reports, exits non-zero; fix → loop goes green.

---

## 6. Self-healing loop (the actual autonomous loop)

```text
while scorecard < 100 and attempts < N:
    1. make verify-fast          # lint + unit + small sim + wasm + backend
    2. if fail:
         classify(log) ∈ {lint, rtl, tb, formal, wasm, backend, web, docs}
         apply minimal diff (never blind file overwrite)
         git diff --check
         retry only the failed stage
    3. if pass:
         make verify-deep         # 1M sim + formal + mutation + synth
    4. update reports/*.json and EXECUTION_LOG.md
    5. if all green: run UI smoke + screenshot + accessibility pass
```

**Escalation rules**
- Two consecutive failures in the same stage → stop, write a root-cause note, ask the user only if a product decision is needed.
- Any change to public interfaces → update `docs/architecture.md` + `llms-full.txt` in the same commit.
- Never commit a benchmark number without the command that produced it.
- Never weaken a test to make it pass; add a regression test first.

**Tooling map**

| Need | Tool |
|---|---|
| HDL sim / lint / synth / formal | WSL Ubuntu: Verilator, Icarus, Yosys, Z3; Docker fallback |
| CPU model / backend | Node 22, Rust 1.96 (`wasm32-unknown-unknown`) |
| Browser verification | Playwright MCP / Chrome DevTools MCP |
| Design review | Better Design MCP (`get-ui-principle`, `get-ux-principle`, review rules) |
| Code review | subagents: `qa-tester`, `security-auditor`, `ast-refactor-pro` |
| Research | `websearch`, `webfetch`, Context7 for WebGPU/WASM/Rust docs |
| Persistence | `EXECUTION_LOG.md`, `reports/`, Basic Memory (optional) |
| Deployment (optional) | Vercel MCP / `vercel` CLI, only after local green |

---

## 7. Definition of Done (this iteration)

- [ ] `make verify` green from a clean clone (or a documented Docker/WSL one-liner).
- [ ] 1,000,000-message full-field regression: 0 mismatches.
- [ ] Formal: BMC + K-induction + covers PASS; mutation score ≥ 90%.
- [ ] At least 3 RTL variants lint + synth with reports.
- [ ] MoldUDP64 gap test passes.
- [ ] Local backend compare: 9 chips, golden = 0 errors, lossy > 0.
- [ ] Web demo runs on the user's AMD Radeon 680M via WebGPU; Canvas2D fallback works.
- [ ] Docker image builds and serves the demo.
- [ ] README claims all traceable; maturity labelled **pre-silicon**.
- [ ] `EXECUTION_LOG.md` has timestamps, commands, results, and open items.

---

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| 322 MHz not closable on Sky130 | High | Publish 2-cycle safe variant; report actual OpenSTA slack; do not claim Fmax without evidence. |
| WebGPU unavailable on user GPU/browser | Medium | Canvas2D fallback + WASM-only mode; report adapter info. |
| OpenLane run too slow/heavy locally | High | Check in configs + small synth reports; run full P&R only in CI/nightly; label as "flow-ready, not run". |
| Rust WASM toolchain missing `wasm32` target | Low | `rustup target add wasm32-unknown-unknown`; fallback to TypeScript model. |
| Scope creep | High | Phase gates; this iteration stops after P5 + docs, P3 full P&R is deferred. |
| Licence contamination | Low | Keep PolyForm terms; third-party notices; no GPL code copied. |

---

## 9. Execution log

See [`EXECUTION_LOG.md`](EXECUTION_LOG.md). Each entry: timestamp, phase, command, result, next action.
