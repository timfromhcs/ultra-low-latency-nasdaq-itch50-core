# ChipLab — Long-Term Plan (2026-11 → 2027-11)

> Status: **ACTIVE**
> Supersedes `AUTONOMOUS_PLAN_V2.md` as the forward-looking roadmap. V1/V2 remain the
> historical execution records. This plan is updated after every release.
> Repo: `timfromhcs/ultra-low-latency-nasdaq-itch50-core`
> Live: <https://chiplab-ten.vercel.app/>
> Rule: **no claim without a command**; every number links to `reports/`.

---

## 1. Where the project is (baseline, 2026-11-03)

| Area | State | Evidence |
|---|---|---|
| RTL protocol | all 22 ITCH opcodes, `tkeep`/`tlast`, 64-bit shares, 128/256/512-bit | `rtl/`, `reports/sim_1m.txt` |
| Full-field regression | **1,000,000 records, 0 mismatches**, 41.290 Gbps model | `reports/sim_1m.txt` |
| Formal | Z3 + CVC5 PASS; Boolector 1.5 unsupported | `reports/formal.json` |
| Mutation | **10/10** RTL mutants killed | `reports/mutation.json` |
| Synthesis | 22,629 / 25,201 / 29,628 cells; 2,228 DFFs | `reports/synth_*.log` |
| MoldUDP64 | single-frame end-to-end PASS; **multi-frame back-pressure open** | `tb/test_mold_pipeline.py` |
| WASM/web | WebGPU compute/render, Canvas2D fallback, OPFS, PWA, 390/1440 | `reports/web-*.png` |
| Backend/MCP | REST + stdio MCP, 5 tools, smoke tests | `mcp/`, `backend/` |
| Distribution | Vercel live, Docker, 83.7 MB EXE, npm/PyPI artifacts | `README.md` |
| CI | **failing** (ubuntu-22.04 `cvc5` missing; gate uses `python`) | GitHub Actions run #6 |
| Automation | hourly scheduled task; agent invocation flag bug found | `reports/heartbeat.log` |

---

## 2. Best-practice research (2026)

| Topic | Source / practice | Consequence for this repo |
|---|---|---|
| AXI4-Stream back-pressure | ZipCPU skid buffer; fpgacpu pipeline skid buffer; AMBA valid/ready rules | Add a skid stage between Mold front-end and depacketizer; hold `tvalid/tdata/tkeep/tlast` stable under `tready=0`. |
| Formal verification | SymbiYosys quickstart; Codasip formal sign-off; formal coverage + mutation | Keep BMC + k-induction + covers; add cover-hit report; mutation must stay ≥90%. |
| ASIC flow | LibreLane (formerly OpenLane 2), Sky130/GF180/IHP; `--dockerized` smoke | Move to LibreLane 2 configs; run a Sky130 hardening smoke; publish slack, not just cells. |
| MCP security | MCP security best practices 2026; CSA agentic MCP guide | Least privilege, strict schemas, read-only tools, audit log with hashed args, stdio-only, no shell/file tool. |
| PWA / WebGPU | MDN PWA best practices; WebGPU/Worker best practices; Lighthouse budgets | Budget: <300 KB JS gzip, TTI <3.5 s, PWA installable, offline shell, WebGPU optional. |
| Release engineering | SemVer, SBOM, SLSA-style provenance, reproducible builds, signed artifacts | Add SBOM (CycloneDX), checksums, tag-driven releases, Docker/npm/PyPI provenance. |
| CI for HDL | Pin tool versions; cache Rust/npm; split fast/deep jobs | Ubuntu 24.04 for cvc5; pin actions; cache cargo; nightly deep run. |

Sources: LibreLane docs, SymbiYosys docs, ZipCPU skid buffer, MCP security guide,
MDN PWA best practices, GitHub Actions docs.

---

## 3. North-star metrics

| Metric | Now | 6 months | 12 months |
|---|---|---|---|
| Full-field records | 1M / 0 mismatches | 10M / 0 | 100M / 0 |
| Formal | Z3 + CVC5 PASS | + Bitwuzla/Yices; cover report | equivalence proof RTL ↔ WASM |
| Mutation score | 100% (10) | ≥95% (50+) | ≥98% (150+) |
| Fmax (Sky130) | not run | OpenSTA slack at 250 MHz | sign-off at 250–322 MHz |
| Mold back-pressure | single-frame | 4-frame back-to-back + skid | 64-frame + loss/gap recovery |
| Order book | WASM top-of-book | RTL BBO | multi-symbol depth + risk checks |
| Web perf | not measured | Lighthouse ≥90, PWA pass | <200 KB JS, 60 fps mobile |
| Distribution | Vercel/Docker/EXE | GHCR signed + npm/PyPI | reproducible releases + SBOM |
| Open issues | R1–R6 | 0 critical | 0 high |

---

## 4. Roadmap

### Phase 0 — Stabilise (now → 2 weeks)
- [ ] Fix CI (Ubuntu 24.04, `python3`, cvc5; cache Rust/npm).
- [ ] Fix hourly heartbeat (`opencode run` positional prompt; UTF-8 log).
- [ ] Add MCP input validation + audit log + `mcp/SECURITY.md`.
- [ ] Add Dependabot, `npm audit`, `cargo audit` (advisory), SBOM.
- [ ] Keep multi-frame Mold as a **known open** item; add a skid-buffer design note.

**Gate:** all GitHub Actions green; heartbeat log proves a tick; MCP smoke + audit pass.

### Phase 1 — Back-pressure + book (2 → 8 weeks)
- [ ] Implement `axis_skid_buffer.sv` (valid/ready, no data loss, 1-deep).
- [ ] Integrate front-end → skid → depacketizer; 4-frame back-to-back test; gap/drop test.
- [ ] Implement `itch_top_of_book.sv`: locate-indexed BBO + volume + last, BRAM inference.
- [ ] Full-field RTL test for BBO against a Python book model.
- [ ] Add `tlast`/frame counters and an explicit `frame_ready`.

**Gate:** 4-frame back-to-back 0 mismatches; BBO 0 mismatches; lint/formal still green.

### Phase 2 — Physical (2 → 4 months)
- [ ] LibreLane Sky130 hardening smoke (`--dockerized --smoke-test`), then full run.
- [ ] OpenSTA slack at 250 MHz and 322 MHz; publish worst path.
- [ ] GF180 + IHP SG13G2 configs, one run each.
- [ ] FPGA target: UltraScale+ / Agilex shell with 100G MAC + Mold front-end.
- [ ] Replace illustrative GDS with an actual LibreLane render or label clearly.

**Gate:** slack report + DRC/LVS status; no "Fmax" claim without a report.

### Phase 3 — System (4 → 8 months)
- [ ] Full MoldUDP64 packet parser with sequence recovery + A/B feed arbitration.
- [ ] Multi-symbol order book (hash table + price ladder), risk checks, top-N.
- [ ] PCIe/DMA or 100G MAC integration; host API for book snapshots.
- [ ] Performance counters: messages/s, gaps, drops, queue occupancy, latency histogram.
- [ ] RTL ↔ WASM equivalence (co-simulation on the same vectors).

**Gate:** end-to-end 100G pcap replay; book matches software at every event.

### Phase 4 — Release / silicon-ready (8 → 12 months)
- [ ] Caravel-style harness; pad ring; timing closure at target; DRC/LVS clean.
- [ ] Reproducible builds; SBOM + SLSA provenance; signed Docker/npm/PyPI.
- [ ] Nightly 10M regression + formal + mutation.
- [ ] Docs: datasheet, integration guide, errata, API reference.
- [ ] Optional shuttle submission; otherwise label "tapeout-ready, not fabricated".

**Gate:** independent reproduction from a clean machine; no fabricated silicon claim.

---

## 5. Immediate sprint (this session)

| # | Task | Command / acceptance |
|---|---|---|
| 1 | Fix CI | Ubuntu 24.04; `python3`; run green on push |
| 2 | Fix heartbeat | `opencode run --session <id> --auto "<msg>"`; UTF-8 log |
| 3 | MCP hardening | strict args, audit hash, `mcp/SECURITY.md`; smoke |
| 4 | Supply chain | Dependabot + `npm audit` + SBOM script |
| 5 | Mold R1 note | document skid-buffer design + keep single-frame proof |
| 6 | Release hygiene | tag `v0.2.1`, changelog, checksums |

---

## 6. Self-healing loop

```text
hourly: heartbeat -> autonomy.mjs next task -> gate
daily:  fast gate (7 checks)
weekly: deep gate (formal matrix, native, 1M RTL, mutation)
monthly: release candidate -> SBOM -> tag -> deploy
on failure: classify (rtl|wasm|web|backend|mcp|pkg|ci), minimal diff, rerun only that stage
never weaken a test; never claim without a report
```

**Escalation:** two failures in the same stage → write root cause, stop that stage, keep
other stages running. Any interface change updates `llms-full.txt` and `docs/architecture.md`.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Mold back-pressure complexity | skid buffer + formal no-loss proof; keep single-frame as fallback |
| LibreLane heavy/slow | Dockerized smoke first; nightly full run |
| CI runner package drift | pin Ubuntu 24.04 + apt versions; cache |
| MCP tool poisoning | static tool list, strict schemas, no file/shell tools, audit |
| WebGPU fragmentation | Canvas2D fallback; PWA budgets |
| Release tokens | build-only until `NPM_TOKEN`/`PYPI_TOKEN`/GHCR permissions are provided |
| Heartbeat does not focus chat | target session ID; document limitation; manual tick always available |

---

## 8. Definition of Done (12 months)

- 10M+ full-field regression, 0 mismatches.
- Formal: BMC + k-induction + covers on ≥3 solvers; equivalence RTL ↔ WASM.
- Mutation ≥95% on ≥50 mutants.
- Sky130 timing/DRC/LVS report; FPGA shell; 100G replay.
- RTL order book with multi-symbol and risk checks.
- Web: Lighthouse ≥90, PWA installable, mobile 60 fps, <200 KB JS.
- Signed reproducible artifacts (EXE, Docker, npm, PyPI) with SBOM.
- CI green; nightly deep gate; documented errata; no fabricated claims.
