<!--
JSON-LD for search engines and AI indexers
{
  "@context": "https://schema.org",
  "@type": "SoftwareSourceCode",
  "name": "ChipLab — ITCH-50 silicon lab",
  "description": "Local-first WebAssembly + WebGPU lab for a NASDAQ ITCH 5.0 parser, with RTL, formal proofs, a Node backend, MCP, npm/PyPI packages, a single EXE, Docker and Vercel.",
  "programmingLanguage": ["SystemVerilog", "Rust", "JavaScript", "Python"],
  "author": { "@type": "Person", "name": "timfromhcs", "email": "timfromhcs@gmail.com", "url": "https://github.com/timfromhcs" },
  "license": "https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core/blob/main/LICENSE.md",
  "keywords": ["systemverilog","verilog","hft","high-frequency-trading","nasdaq-itch","itch50","market-data","low-latency","fpga","asic","webassembly","webgpu","rust","mcp","formal-verification","openlane","sky130","orderbook"]
}
-->

# ChipLab — ITCH-50 silicon lab

[![CI](https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core/actions/workflows/ci.yml/badge.svg)](.github/workflows/ci.yml)
[![RTL](https://img.shields.io/badge/RTL-SystemVerilog-1f6feb)](rtl/)
[![WASM](https://img.shields.io/badge/WASM-50%20KB-3ef07a)](web/wasm/chiplab_core.wasm)
[![WebGPU](https://img.shields.io/badge/WebGPU-compute%20%2B%20render-3ef07a)](web/gpu.js)
[![Formal](https://img.shields.io/badge/Formal-Z3%20%2B%20CVC5%20PASS-success)](reports/formal.json)
[![Maturity](https://img.shields.io/badge/Maturity-pre--silicon-orange)](#honest-limits)

**Run the feed. See the silicon.** A WebAssembly twin of a NASDAQ TotalView-ITCH 5.0
parser, measured on your own hardware, with a WebGPU order-book visualisation and a
single-file local backend. Pre-silicon, reproducible, and honest about what is not proven.

**[Live demo](https://chiplab-ten.vercel.app/)** · **[Local demo](http://127.0.0.1:4173)** after `node backend/server.mjs`.

![ChipLab desktop demo](reports/web-1440-depth.png)

---

## What this is

- An **RTL ITCH 5.0 parser** (`rtl/`) that decodes all 22 official opcodes, preserves
  reference data, handles `tkeep`/`tlast`, and ships 128/256/512-bit variants.
- A **MoldUDP64 front-end** (`moldudp64_frontend.sv` + `depacketizer.sv`) with IP/UDP
  filtering and sequence-gap detection (single-frame end-to-end proof; multi-frame
  backpressure is tracked as an open limitation).
- A **field-accurate reference model** in Python (`tb/itch_model.py`) and Rust
  (`wasm-core/`), cross-checked record-by-record.
- A **local-first web app**: WASM in a Worker, WebGPU compute for price bins and
  latency histograms, Canvas2D fallback, OPFS persistence, PWA/offline.
- A **Node backend / MCP server / REST API / npm package / PyPI package / single EXE /
  Docker image / Vercel build** around the same WASM core.
- A **native Vulkan/DX12 compute runner** (`native/`) using `wgpu`, with an opt-in
  Windows process boost.
- **Verification evidence**: 1,000,000-message full-field regression, Z3 + CVC5 formal
  proofs, synthesis matrix, mutation tests, browser gates.

## What this is not

- **Not silicon-proven.** There is no tapeout. Fmax is not signed off.
- **Not a trading system.** No order routing, no live feed, no investment advice.
- **Not a zero-cycle wire-to-output parser.** The honest latency is:
  one clock from `s_axis_tdata` into the window register + one clock to the registered
  output = **2 clocks (6.20 ns at 322.26 MHz)**. The async bypass is valid in the same
  cycle as the window, one clock after ingress.
- **Not a full multi-frame MoldUDP64 MAC integration yet.** The blocks are verified
  separately and the single-frame pipeline passes; back-to-back flow control is open.

---

## Quickstart

```bash
git clone https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core.git
cd ultra-low-latency-nasdaq-itch50-core

# 1) Web demo + local API (Node 22, no npm dependencies)
node backend/server.mjs
# open http://127.0.0.1:4173
```

The web app also works as a static PWA. The browser keeps its own run history in OPFS;
nothing is uploaded.

### Choose your runtime

| Runtime | Command | What you get |
|---|---|---|
| Web + API | `node backend/server.mjs` | WebGPU/WASM demo, `/api/*` |
| CLI | `node backend/run.mjs --compare --count 1000000` | 8-chip comparison |
| Single EXE | `npm run build:exe && dist\chiplab.exe` | one file, embedded web + WASM |
| Docker | `docker compose up --build` | same demo at `localhost:4173` |
| Vercel | `npx vercel` (or MCP) | static app + stateless `/api/*` |
| MCP | `node mcp/server.mjs` | tools for agents |
| npm | `npm i @chiplab/core` | WASM core + CLI |
| PyPI | `pip install chiplab-itch` | Python reference model + CLI |

### Verification

```bash
# Linux/WSL toolchain: verilator, yosys, iverilog, z3, cvc5, python cocotb/pytest
make lint                # Verilator, 0 warnings
python tb/itch_model.py --count 100000 --out tb/vectors
make sim                 # full-field Verilator regression
make formal              # Z3 BMC + k-induction + covers
./formal/solver_matrix.sh
python -m pytest -q tb/test_model.py
node scripts/wasm_smoke.mjs && python scripts/check_wasm_fixture.py
node backend/run.mjs --compare --count 1000000
node mcp/client_smoke.mjs
node scripts/build_vercel.mjs && node scripts/test_vercel_api.mjs
```

---

## Measured evidence

All numbers below are **model/simulation results at 322.26 MHz**, not silicon.
Reports live in [`reports/`](reports/).

| Check | Result | Evidence |
|---|---|---|
| Full-field RTL regression | **1,000,000 / 1,000,000 records, 0 mismatches**, 31,383,973 bytes, 1,961,516 cycles, 41.290 Gbps | `reports/sim_1m.txt` |
| Fields checked | type, flags, length, locate, tracking, timestamp, ref, new-ref, shares (64b), stock, price, match, MPID, printable, event, payload checksum | `tb/sim_main.cpp` |
| Reference model | independent Python, all 22 opcodes | `tb/itch_model.py` |
| WASM ↔ Python | 10,000 records, 0 mismatches | `scripts/check_wasm_fixture.py` |
| Formal | **Z3 PASS, CVC5 PASS** (BMC + k-induction + covers); Boolector 1.5 unsupported | `reports/formal.json` |
| Mutation | **10/10 RTL mutants killed** (length, offsets, share width, flags, append, consume) | `reports/mutation.json` |
| Synthesis 128-bit | 22,629 cells, 2,228 DFFs | `reports/synth_128.log` |
| Synthesis 256-bit | 25,201 cells | `reports/synth_256.log` |
| Synthesis 512-bit | 29,628 cells | `reports/synth_512.log` |
| Native Vulkan (Radeon 680M) | 200,000 records in **7.85 ms**, bins match CPU exactly | `reports/native_bins.bin` |
| Browser demo | 1,000,000 messages in **664 ms**, 0 errors, WebGPU compute | `reports/web-1440-depth.png` |
| Single EXE | 83.7 MB, embedded 15 web files + 50 KB WASM | `dist/chiplab.exe` |
| Docker image | builds and serves `/api/health` | `Dockerfile` |
| Vercel | **READY**, live at `https://chiplab-ten.vercel.app/`; 100k run, 0 errors | `reports/web-vercel.png` |
| npm package | `npm pack` + clean install parses 1,000 records | `packages/npm/` |
| PyPI package | wheel builds and `selfcheck` covers all 22 opcodes | `packages/python/` |

**Throughput model.** 128-bit @ 322.26 MHz = 41.25 Gbps line rate. The parser consumes
at most one message per cycle; ITCH average message size (~30 B) means the useful
message rate is ~177 M msg/s in the model, not a blanket 165 Gbps at 512-bit. The
512-bit variant removes input-side byte starvation but does not multiply parser slots.

**Latency model.** 1 clock from window to registered output; 2 clocks from
`s_axis_tdata`. The 452/484-bit output mux and 1024-bit shifter are the critical path;
a 322 MHz sign-off requires OpenSTA/OpenLane, which is **not** claimed here.

---

## Architecture

```
AXI4-Stream 128/256/512
        │
        ▼
┌─────────────────────────────┐     ┌──────────────────────────────┐
│ moldudp64_frontend.sv       │     │ itch_shifter.sv              │
│ L2/L3/L4 filter, Mold hdr,  │────▶│ tkeep, cleared append,       │
│ sequence gap                │     │ 512-bit sliding window       │
└─────────────────────────────┘     └──────────────┬───────────────┘
                                                   │
                                    ┌──────────────▼───────────────┐
                                    │ itch_parser_core.sv          │
                                    │ all 22 opcodes, full payload │
                                    │ 64-bit shares, pre-trigger   │
                                    └───────┬──────────────┬───────┘
                                            │              │
                              ┌─────────────▼───┐   ┌──────▼─────────────┐
                              │ registered egress│   │ async bypass       │
                              │ 1 cycle          │   │ same-cycle window  │
                              └──────────────────┘   └────────────────────┘

Offline twin: Rust → wasm32 → Worker / Node / MCP / npm / EXE / Docker / Vercel
Visualisation: WebGPU compute (bins + histogram) + WebGPU render / Canvas2D fallback
```

### Chip models

| ID | Model | Latency model | Purpose |
|---|---|---|---|
| 0 | Scalar reference | 0 | golden |
| 1 | ITCH-50 v2 | 1 cycle after window | this RTL |
| 2 | ITCH-50 safe | 2 cycles | timing-closed variant |
| 3 | Enyx-class | 3 cycles | commercial-class comparison |
| 4 | NovaSparks-class | 2 cycles | comparison |
| 5 | Lossy admin-drop | 1 cycle | negative control, must fail |
| 6 | MoldUDP64 front-end | 3 cycles | L2–L4 + Mold |
| 7 | Parser + top-of-book | 2 cycles | parse-to-book |

---

## Web demo

![Mobile demo](reports/web-390-run.png)

- **WebGPU compute** bins prices and latency on the GPU; **WebGPU render** draws the
  density. On devices without WebGPU, Canvas2D draws the same data.
- **Worker-isolated WASM**: the UI stays responsive while 1M records are generated,
  parsed and packed.
- **OPFS persistence**: the last runs and settings stay in this browser. No account,
  no upload. `navigator.storage.persist()` is requested.
- **PWA/offline**: service worker caches the app shell and WASM.
- **Responsive**: 390 px bottom navigation, 768 px stack, 1440 px three-column lab.

The demo is a dense tool, not a marketing page: tape, depth density, latency histogram,
chip comparison and containers share one scan path.

---

## Local API

```bash
curl -s http://127.0.0.1:4173/api/health
curl -s -X POST -H 'content-type: application/json' \
  -d '{"chip":1,"count":100000,"seed":1337}' http://127.0.0.1:4173/api/run
curl -s -X POST -H 'content-type: application/json' \
  -d '{"count":100000,"seed":1337}' http://127.0.0.1:4173/api/compare
```

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/health` | GET | wasm version, chips, host |
| `/api/chips` | GET | chip registry |
| `/api/run` | POST | one chip + sample records + book |
| `/api/compare` | POST | all chips vs golden |
| `/api/book` | POST | top-of-book |

**MCP** (`node mcp/server.mjs`) exposes the same five operations:
`chiplab.chips`, `chiplab.run`, `chiplab.compare`, `chiplab.book`,
`chiplab.formal_status`.

---

## Packages

```bash
# npm
cd packages/npm && npm pack
npm install ./chiplab-core-0.2.0.tgz

# PyPI
cd packages/python
python -m build
pip install dist/chiplab_itch-0.2.0-py3-none-any.whl
chiplab-itch selfcheck --count 100000
```

Publishing requires `NPM_TOKEN` / `PYPI_TOKEN`; the repository only builds and tests
locally. The `@chiplab/core` package bundles the same 50 KB WASM artifact used by the
web app, Node and the EXE.

---

## Single EXE, Docker, Vercel

| Target | Build | Run |
|---|---|---|
| EXE | `npm run build:exe` | `dist\chiplab.exe --port 4190` |
| Docker | `docker build -t chiplab:0.2.0 .` | `docker run --rm -p 4173:4173 chiplab:0.2.0` |
| Vercel | `node scripts/build_vercel.mjs` | `vercel` / Vercel MCP |

The EXE embeds the web assets and the WASM; it serves the same API and opens the browser.
The Docker image is a non-root Node 22 alpine runtime with a healthcheck.
The Vercel build is static-first (`public/`) plus stateless `api/*` functions; per-user
data stays in the browser (OPFS/IndexedDB). For server-side persistence, Vercel
Sandbox Drives are a separate, paid option — not used by this repository.

---

## Verification stack

- **RTL**: Verilator lint, full-field 1M regression, cocotb (`tb/test_itch.py`),
  Mold front-end/depacketizer tests (`tb/test_mold*.py`).
- **Formal**: `formal/itch_formal.sv` checks pre-trigger equivalence, class exclusivity,
  legal lengths, register equivalence and flow control; `formal/run_formal.sh` runs BMC,
  k-induction and covers; `formal/solver_matrix.sh` records each solver.
- **Mutation**: `tools/mutate.py` injects RTL mutants and requires the suite to kill them.
- **Reference model**: Python and Rust independently, compared field-by-field.
- **Browser**: Playwright at 390/1440, console-error gate, WebGPU/Canvas2D paths.
- **Packages**: clean npm/PyPI installs, MCP handshake, Vercel handler smoke, Docker health.

---

## Repository map

```
rtl/                 SystemVerilog parser, shifter, Mold front-end/depacketizer
formal/              SVA harness, SymbiYosys runner, solver matrix
tb/                  Python model, vector generator, Verilator/Cocotb tests
wasm-core/           Rust → wasm32 core (parser, generator, chips, book)
web/                 PWA: UI, Worker, WebGPU, Canvas2D, OPFS
backend/             Node server, CLI, WASM wrapper
mcp/                 stdio MCP server + smoke client
api/                 Vercel serverless handlers
native/              Rust wgpu Vulkan/DX12 compute runner + optional boost
packages/npm/        @chiplab/core
packages/python/     chiplab-itch
scripts/             build/gate/synth/formality/heartbeat/autonomy tools
docs/guides/         zero-to-hero guides (EN / DE / FR)
AUTONOMOUS_PLAN_V2.md
EXECUTION_LOG.md
reports/             measured evidence (logs, JSON, screenshots)
```

---

## Zero-to-hero guides

- [English](docs/guides/en/zero-to-hero.md)
- [Deutsch](docs/guides/de/zero-to-hero.md)
- [Français](docs/guides/fr/zero-to-hero.md)

Each guide covers: run the demo, read the tape/book, verify a record, run the formal
proof, build the EXE/Docker image, and understand the honest limits.

Planning and research: [`AUTONOMOUS_PLAN_V2.md`](AUTONOMOUS_PLAN_V2.md),
[`docs/research-v2.md`](docs/research-v2.md), [`EXECUTION_LOG.md`](EXECUTION_LOG.md).

---

## Honest limits (read this)

1. **No tapeout, no silicon.** "Silicon lab" means executable RTL + digital twin.
2. **No Fmax sign-off.** 322.26 MHz is the target/model clock. OpenLane configs are
   flow-ready; full P&R and slack reports are not claimed.
3. **Multi-frame MoldUDP64 backpressure is experimental.** Single-frame end-to-end
   passes; back-to-back frames are tracked in `AUTONOMOUS_PLAN_V2.md` (R1).
4. **WebGPU numbers are visualisation samples.** Totals come from the exact parser;
   GPU bins use the same integer prices. `f32` is only used for bar heights.
5. **The feed is synthetic.** Seeded generation is reproducible; it is not a captured
   NASDAQ day.
6. **The native boost is opt-in.** `--boost` sets Windows priority/affinity; it is not
   applied silently and is restored when the process exits.

---

## Roadmap

- [ ] AXI-Stream skid/FIFO for multi-frame MoldUDP64 back-to-back.
- [ ] Full RTL top-of-book (currently a WASM/visual model).
- [ ] OpenLane P&R + OpenSTA slack for Sky130/GF180/IHP.
- [ ] Bitwuzla/Yices in the solver matrix.
- [ ] Optional Vercel Sandbox/Drives recipe for team persistence.
- [ ] Published npm/PyPI artifacts and GHCR image (tokens required).

---

## Licence & attribution

PolyForm Small Business Dual-License 1.0.0. Free for entities under **$100,000 USD**
annual gross revenue with the mandatory attribution string:

```text
Hardware powered by ultra-low-latency-nasdaq-itch50-core by @timfromhcs
(https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core)
```

Enterprise/white-label: `timfromhcs@gmail.com`. See [LICENSE.md](LICENSE.md).

**Keywords:** NASDAQ ITCH 5.0 parser, ITCH50, market data, HFT, FPGA, ASIC, SystemVerilog,
WebAssembly, WebGPU, Rust, MCP, formal verification, Z3, CVC5, SymbiYosys, OpenLane,
Sky130, order book, MoldUDP64, low latency, silicon lab.
