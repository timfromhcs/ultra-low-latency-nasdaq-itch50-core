# ChipLab — Long-Term Plan (2026-11 → 2027-11)

> Status: **ACTIVE**
> Supersedes `AUTONOMOUS_PLAN_V2.md` as the forward-looking roadmap. V1/V2 remain the
> historical execution records. This plan is updated after every release.
> Current release: **v0.3.1 "Local Cloud"** (2026-11-03) — see `STABLE_RELEASE_PLAN.md`.
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
| Mutation | **19/19** mutants killed (10 parser + 9 BBO) | `reports/mutation*.json` |
| Synthesis | 22,629 / 25,201 / 29,628 cells; 2,228 DFFs | `reports/synth_*.log` |
| MoldUDP64 | **5 frames back-to-back PASS** (4 valid + 1 gap + 1 drop) | `tb/test_mold_multi.py` |
| WASM/web | WebGPU compute/render, Canvas2D fallback, OPFS, PWA, 390/1440 | `reports/web-*.png` |
| Backend/MCP | REST + stdio MCP, **12 tools**, local cloud JSON store | `mcp/`, `backend/` |
| Distribution | **v0.3.0 GitHub Release** (EXE, npm tgz, wheel/sdist, SBOM, SHA-256), Docker, Vercel | `releases/tag/v0.3.0` |
| CI | **green** (Ubuntu 24.04, Icarus cocotb, weekly deep formal) | GitHub Actions run #24 |
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
| Mutation score | 100% (19) | ≥95% (50+) | ≥98% (150+) |
| Fmax (Sky130) | not run | OpenSTA slack at 250 MHz | sign-off at 250–322 MHz |
| Mold back-pressure | single-frame | **4+ frames back-to-back PASS** | 64-frame + loss/gap recovery |
| Order book | WASM top-of-book | RTL BBO | multi-symbol depth + risk checks |
| Web perf | not measured | Lighthouse ≥90, PWA pass | <200 KB JS, 60 fps mobile |
| Distribution | Vercel/Docker/EXE | GHCR signed + npm/PyPI | reproducible releases + SBOM |
| Open issues | R1–R6 | 0 critical | 0 high |

---

## 4. Roadmap

### Phase 0 — Stabilise (now → 2 weeks)
- [x] Fix CI (Ubuntu 24.04, `python3`, cvc5 optional; formal smoke depth 8).
- [x] Fix hourly heartbeat (`opencode run` positional prompt; UTF-8 log; dry-run).
- [x] Add MCP input validation + audit log + `mcp/SECURITY.md`.
- [x] Add Dependabot, SBOM (`reports/sbom.json`); `npm audit` in release checklist.
- [x] Keep multi-frame Mold as a **known open** item; add a skid-buffer design note.
- [x] Add and test `axis_skid_buffer.sv` (200 random beats, no loss).
- [x] Verify the CI run is green on GitHub (run #24).
- [x] Move the expensive 20-step formal proof to a weekly workflow; PR CI runs
      lint + 50k full-field + model + cocotb on Icarus.

**Gate:** all GitHub Actions green; heartbeat log proves a tick; MCP smoke + audit pass.

### Phase 1 — Back-pressure + book (2 → 8 weeks)
- [x] Implement `axis_skid_buffer.sv` (valid/ready, no data loss, 1-deep).
- [x] Back-to-back frames with gap + drop: **5 frames, 28 records, 0 mismatches**
      (`tb/test_mold_multi.py`). No skid stage needed functionally; the front-end
      holds beats under back-pressure.
- [x] Add `tlast`/frame counters and an explicit `frame_ready` / `frame_end`.
- [x] Implement `itch_top_of_book.sv`: locate-indexed BBO, last trade and volume.
- [x] Random RTL test vs. a Python book model: **400 events, 0 mismatches**, plus
      **100 events back-to-back at 1 event/cycle with no stall** (`tb/test_book.py`).
- [x] No rescan stall: per-locate price-level table (16 bid + 16 ask) with a 16-way
      max/min reduction; 2-cycle latency.
- [x] 4-way set-associative order lookup (4 compares, was 256).
- [ ] Physical timing sign-off of the level table + reduction (Phase 2).
- [x] End-to-end parser -> BBO wrapper: 152 raw messages, 0 mismatches
      (`rtl/itch_top_book.sv`, `tb/test_book_top.py`).
- [x] Pipeline downstream back-pressure: `m_axis_tready` through the depacketizer and
      pipeline, beats held until accepted; 329 bytes under random stalls, no loss.
- [x] Optional skid/FIFO stage for timing isolation at higher clock rates:
      `itch_top_book #(.INGRESS_SKID(1))` inserts the 2-entry `axis_skid_buffer` on
      ingress. The 152-message parser→BBO test runs against both builds with periodic
      input gaps and produces identical BBO and counters.

**Gate:** multi-frame 0 mismatches ✅; BBO 0 mismatches ✅; lint/formal still green.

### Phase 2 — Physical (2 → 4 months)
- [x] Yosys area estimate for the BBO: 62,017 cells at 32/4/4 (not optimized,
      no timing claim) — `scripts/synth_book.sh`, `reports/synth_book.json`.
- [x] LibreLane toolchain: **3.0.17 smoke test passed** (Classic flow 80/80, DRC ✅,
      LVS ✅, RC 0) via Docker Desktop + `ghcr.io/librelane/librelane:3.0.17` with a
      cached PDK volume; see `openlane/README.md`.
- [ ] Full LibreLane Sky130 run: **attempted, not achievable with the current pin
      count**. Without the resizer skips it stalls >1 h on the −9 ns path; with the
      resizer steps skipped, GlobalRouting fails with **GRT-0116 congestion** at the
      700×700 µm die with ~1,100 top-level pins (484-bit `raw_order_data`, 512-bit
      `raw_payload`). Needs a narrow physical wrapper and a fitted/larger die.
- [x] Narrow physical wrapper `itch_host_wrap` (128-bit AXI4-Stream ingress, 32-bit
      host register port with counters + last-message fields, no debug payload bus):
      test passes (2 messages, type/locate/shares/ref read back), lint clean.
- [x] Wrapper pre-PnR STA: **WNS −8.62 ns at 3.10 ns** (ss), Fmax **85.34 MHz**, worst
      path FF → FF; the debug-bus endpoint is gone (`reports/openlane_wrap-sta.json`).
- [ ] Full P&R of the wrapper: **blocked by placement/routing stability** — 700 µm
      fails GlobalRouting congestion, 1400 µm diverges in GlobalPlacement (GPL-0305)
      with the 1,533-terminal clock; needs clock planning/fitted floorplan.
- [x] Pre-PnR OpenSTA slack published at both targets (sky130, sky130_fd_sc_hd):
      250 MHz → **WNS −8.27 ns**, 322 MHz → **WNS −9.14 ns**, both ss/100C/1.60 V;
      Fmax estimate **≈81.5 MHz**, worst path `_35427_` → `raw_payload[0]`.
      Artifact `reports/openlane_sky130-250mhz-sta.json`. This is pre-PnR, not sign-off.
- [ ] Post-route STA with the full flow (blocked on the P&R above).
- [x] GF180 pre-PnR STA run: **WNS −19.87 ns at 3.10 ns** (ss/125 °C), Fmax **43.54 MHz**,
      worst path FF → `raw_order_data[260]` (`reports/openlane_gf180-sta.json`).
- [x] IHP SG13G2 pre-PnR STA run: **WNS −3.08 ns at 3.10 ns** (slow/125 °C), Fmax
      **161.9 MHz**, hold WNS −0.052 ns, worst path FF → FF
      (`reports/openlane_ihp-sta.json`).
- [ ] FPGA target: UltraScale+ / Agilex shell with 100G MAC + Mold front-end.
- [x] Replace illustrative GDS with an actual LibreLane render or label clearly: the
      render is explicitly labeled an illustrative floorplan sketch in
      `docs/images/README.md` and errata E9; it is not used as a sign-off artifact.

**Gate:** slack report + DRC/LVS status; no "Fmax" claim without a report.

### Phase 3 — System (4 → 8 months)
- [x] A/B frame arbitration: sequence-based selection, redundancy window, loser discard,
      gap pulse (`rtl/mold_feed_arbiter.sv`, 6-frame test).
- [x] A/B system integration: two Mold Ethernet pipelines → arbiter → one ITCH stream
      (`rtl/mold_ab_system.sv`; 2 feeds, 10 records, 1 gap).
- [x] Sequence recovery request generator: missing-range request, replay recovery,
      timeout resync and duplicate rejection (`rtl/mold_recovery.sv`, 4-accept test).
- [x] Arbiter recovery mode: a gap requests the missing range and drops the
      out-of-order frames; the replay is accepted in order; timeout abandons and
      force-accepts (`recovery_en`, test markers [1,2,3,6]).
- [x] Replay loop validated with two loss events: multi-gap repair markers [1..8],
      2 requests, no abandon (the test acts as the replay source).
- [ ] Hardware/upstream retransmit requester (network protocol) — out of scope for the
      local core; the request interface is the contract.
- [x] Multi-symbol order book: 16 locates, 16 price levels per side, **top-4 depth**
      output, 400-event + 100 back-to-back tests.
- [x] Risk checks: per-order share limit and price collar vs. the last trade, with a
      reject counter (`cfg_max_shares`, `cfg_collar`); 3-test book suite covers both.
- [x] Host book-snapshot block (`rtl/itch_book_snapshot.sv`): per-locate top-of-book,
      last trade, volume and top-4 depth, one-cycle registered read port with a hit flag
      and an update counter; test reads two locates, a miss, stability and a re-read.
- [ ] PCIe/DMA or 100G MAC integration.
- [x] Performance counters (`rtl/itch_metrics.sv`): message/byte totals, gap/drop
      pulses, free-running cycle counter, max queue occupancy and an 8-bin
      inter-message gap histogram. Wired into `itch_top_book` (`metrics_*`);
      test: 9-message histogram and 152-message integration (`tb/test_metrics.py`,
      `tb/test_book_top.py`).
- [x] RTL ↔ WASM equivalence on the same vectors: **100,000 records, every canonical
      field equal** (`scripts/rtl_wasm_equiv.mjs`, weekly `equivalence` job).

**Gate:** end-to-end 100G pcap replay; book matches software at every event.

### Phase 4 — Release / silicon-ready (8 → 12 months)
- [ ] Caravel-style harness; pad ring; timing closure at target; DRC/LVS clean.
- [x] SBOM + SLSA provenance: `actions/attest-build-provenance` signs the EXE, npm
      tarball and Python wheel/sdist in `release.yml` and `exe.yml` (verifiable with
      `gh attestation verify`); Docker publishes `provenance: mode=max` + SBOM.
- [x] Reproducible Python packaging: `scripts/repro_python.sh` builds the wheel and
      sdist twice with `SOURCE_DATE_EPOCH=1700000000`; the wheel is byte-identical and
      the sdist is byte-identical after `scripts/normalize_sdist.sh` (fixed order,
      mtime, owner, no gzip timestamp). `release.yml` applies both. Artifact:
      `reports/repro_python.json`.
- [x] Docker supply chain: `provenance: mode=max` + SBOM attestation + **keyless
      cosign signature** (`docker-publish.yml`, `id-token: write`).
- [x] WASM reproducible build: `wasm-core/rust-toolchain.toml` pins rustc 1.98.1 and
      the shipped binary (`web/wasm`, `public/wasm`, `packages/npm/wasm`) is rebuilt
      from it. `scripts/repro_wasm.sh` (`make repro-wasm`) → two clean builds and the
      committed artifact are all `d2b5f58f…` (50,322 bytes), **matchesCommitted: true**.
- [ ] cosign/sigstore signatures for npm/PyPI artifacts.
- [x] Mutation: 9 parser→BBO mutants killed (`tools/mutate_book.py`,
      `reports/mutation_book.json`); weekly `mutation` job in the Formal workflow.
- [x] Nightly 10M regression + formal + mutation (`.github/workflows/nightly.yml`,
      daily 02:40 UTC, default 10,000,000 messages, calls the reusable `Formal`
      workflow). Verified locally: 10M messages, **0 mismatches**.
- [x] Docs: datasheet, integration guide, errata and API reference
      (`docs/datasheet.md`, `docs/integration-guide.md`, `docs/errata.md`,
      `docs/api.md`; served through the 12-key `chiplab.docs` catalog).
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
| CI runner package drift | pin oss-cad-suite 2026-11-03 (cached) for formal; pin Ubuntu 24.04 for the rest |
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
