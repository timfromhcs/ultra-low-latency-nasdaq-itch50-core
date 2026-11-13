# SOTA research — ChipLab v2

This note records the sources and decisions behind `AUTONOMOUS_PLAN_V2.md`. It is not a
claim that every source was benchmarked locally.

## 1. ITCH / market-data parsers

| Source | Finding | Decision |
|---|---|---|
| Nasdaq TotalView-ITCH 5.0 specification | 22 opcodes, variable lengths, MoldUDP64 delivery; the FPGA feed is unshaped at 10/40 Gb. | Official lengths and payloads are the reference; tests cover all 22. |
| Fractal Scientific / Marc Battyani, *sub-25 ns open-source NASDAQ ITCH FPGA parser* | 8 cycles @ 322.265 MHz = 24.8 ns last-byte-to-command; parses Ethernet + IPv4 + UDP + MoldUDP64 + ITCH as bytes arrive; 297-bit canonical output. | We added a MoldUDP64 front-end and a strict latency reference point; we do not claim 24.8 ns. |
| NovaSparks (same author) | First pure-FPGA feed handler (2008), full parser + order book + symbol mapping. | Parser alone is not the product; reference data and a book stage matter. |
| Vitis HLS ITCH feed handler (2026) | 6 cycles parse-to-book at 250 MHz = 24 ns. | Measure parse-to-book, not parse alone; our WASM book stage is explicit. |
| Columbia ELEN 4840 proposal (2026) | Parser + sorted hardware order book, CPU vs FPGA baseline, 2-byte length framing. | Synthetic framing and CPU baseline are legitimate; document them. |
| BRH *FPGA HFT Order Book* series (2026) | L2→UDP→Mold→ITCH pipeline, `tlast`, sequence gaps, hash-table/XOR-folded book. | `tlast`/gap detection are table stakes; our RTL gap logic is verified, the book is WASM-side. |
| TechRxiv 2025, speculative macro-driven ITCH parser | Canonical output with one-cycle-class decode. | Speculation is fine with validity framing; our combinational decode is registered. |

## 2. Verification

- Cocotb 2.x + Verilator 5 with **full-field** checks, not type/locate only.
- Independent golden models in Python and Rust; cross-checked (10k records, 0 mismatches).
- SymbiYosys + Z3/CVC5 for BMC, k-induction, covers. Boolector 1.5 in Ubuntu 24.04 is too
  old for the generated SMT-LIB path; record it as unsupported rather than hiding it.
- Mutation testing (10 mutants) proves the regression is not vacuous.
- Synthesis evidence in `reports/synth_*.log`. Two physical flows are signed off
  (wrapper 25 ns, reduced level table 42 ns; `reports/openlane_*_full.json`); the full
  32/4/4 level table and the BBO block are not, and pre-PnR STA is never called sign-off.

## 3. Browser / WebGPU / persistence

| Source | Finding | Decision |
|---|---|---|
| MDN WebGPU | Compute + render, secure context, Chrome/Edge 113+. | WebGPU compute for bins/histogram, WebGPU render for density; Canvas2D fallback. |
| MDN OPFS / DuckDB-WASM OPFS article (2026) | OPFS is a per-origin sandboxed file system with random access; IndexedDB is universal. | Run history in OPFS with IndexedDB fallback; no upload. |
| container2wasm | Converts containers to WASM for browser/WASI; a full Linux container is heavy. | Implement a lightweight **chip container** (WASM module + manifest + limits), not a Linux VM. |
| Vercel Sandbox / Drives docs (2026) | Persistent sandboxes and drives exist server-side; stateless functions otherwise. | Static-first Vercel + browser OPFS by default; Sandbox/Drives documented as optional/paid. |
| Node.js SEA docs (Node 22 `--experimental-sea-config`) | One JS blob injected into a copy of `node.exe`; postject historically required. | Build `chiplab.exe` with embedded assets + WASM; 83 MB because it carries Node. |
| WebGPU native examples | WebGPU + WASM runs on user hardware; HTTPS/localhost required. | Local demo uses localhost; Vercel uses HTTPS. |

## 4. Native / hardware

- `wgpu` enumerates **AMD Radeon 680M backend=Vulkan** on this host; DX12 and GL also
  appear. A compute shader bins 200k records in **7.85 ms**; CPU bins match exactly.
- Windows process boost is `SetPriorityClass(HIGH_PRIORITY_CLASS)` plus optional affinity;
  it is opt-in (`--boost`), not silent.
- No Fmax claim: the 1024-bit shifter + 484-bit mux needs OpenSTA/OpenLane to sign off.

## 5. Packaging / distribution

- npm: `@chiplab/core` bundles the 50 KB WASM and a CLI; `npm pack` + clean install tested.
- PyPI: `chiplab-itch` uses only stdlib; wheel + sdist built; `selfcheck` covers 22 opcodes.
- Docker: Node 22 alpine, non-root, healthcheck; image builds and serves `/api/health`.
- Vercel: `public/` static + `api/*` serverless; handlers invoked in a local harness.
- MCP: stdio JSON-RPC, five tools; smoke client passes.
- Single EXE: Node SEA; embedded 11 web files + WASM; API and static both return 200.

## 6. Autonomy

- `autonomy/queue.json` + `scripts/autonomy.mjs` run one gate per tick and record the exact
  command/result.
- Windows Scheduled Task `ChipLabHeartbeat` runs hourly and resumes the newest OpenCode
  session in this project with a bounded prompt. Honest limitation: a scheduled task
  cannot guarantee focus of this exact chat window.
- `reports/heartbeat.log` and `reports/autonomy.log` are append-only evidence.

## 7. Sources

- https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHSpecification.pdf
- https://github.com/mbattyani/sub-25-ns-nasdaq-itch-fpga-parser
- https://hugobrh.dev/posts/Trademaxxer_MoldUDP64/
- https://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/proposals/Market-Data-Parser.pdf
- https://www.techrxiv.org/doi/10.36227/techrxiv.174803766.68744651
- https://developer.mozilla.org/en-US/docs/Web/API/WebGPU_API
- https://duckdb.org/2026/09/18/opfs-wasm
- https://github.com/container2wasm/container2wasm
- https://vercel.com/kb/guide/vercel-sandbox-duration-and-persistence
- https://nodejs.org/api/single-executable-applications.html
- https://github.com/YosysHQ/sby
- https://openlane.readthedocs.io/
