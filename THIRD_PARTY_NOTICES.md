# Third-party notices

| Component | Licence | Use |
|---|---|---|
| Space Mono | SIL Open Font License 1.1 | UI font (loaded from Google Fonts, system fallback) |
| Rust `wgpu`, `naga`, `pollster`, `bytemuck` | MIT / Apache-2.0 | native Vulkan/DX12 compute runner |
| Node.js | MIT | runtime for backend, MCP, SEA |
| esbuild | MIT | build-time bundling |
| postject | MIT | build-time SEA injection |
| Verilator | LGPL-3.0 / Artistic-2.0 | simulation/lint (not linked into the design) |
| Yosys | ISC | synthesis/formal (not linked into the design) |
| SymbiYosys / yosys-smtbmc | ISC | formal driver |
| Z3 | MIT | SMT solver |
| CVC5 | BSD-3-Clause | SMT solver |
| Boolector | MIT | SMT solver (unsupported path in the current matrix) |
| OpenLane / Sky130 / GF180 / IHP PDKs | Apache-2.0 / per-PDK | flow-ready configs, not run for sign-off |
| NumPy, Scapy, Cocotb, pytest | BSD / Apache / MIT | test-time only |

No GPL code has been copied into the RTL or the WASM parser. The repository's own code is
PolyForm Small Business 1.0.0.
