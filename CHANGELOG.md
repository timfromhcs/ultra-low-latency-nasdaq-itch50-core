# Changelog

## 0.2.0 — 2026-11-03

### Added
- Rust → wasm32 core: parser, deterministic generator, 8 chip models, top-of-book.
- Web app with WebGPU compute/render, Canvas2D fallback, Worker isolation, OPFS history, PWA.
- Node backend + REST API + MCP stdio server.
- npm `@chiplab/core` and PyPI `chiplab-itch` packages.
- Single-file Windows EXE (Node SEA), Docker image, Vercel static + API build.
- Native `wgpu` Vulkan/DX12 compute runner with opt-in Windows priority boost.
- MoldUDP64 front-end, depacketizer, sequence-gap detection, single-frame pipeline test.
- Formal v2 harness + solver matrix (Z3, CVC5).
- Zero-to-hero guides in EN/DE/FR, solver/synthesis reports, autonomy heartbeat.

### Changed
- `itch_shifter.sv`: `tkeep`, cleared append window, generic 128/256/512 width.
- `itch_parser_core.sv`: all 22 opcodes, full payload, 64-bit shares, valid pre-trigger.
- `itch_top.sv`: tkeep/tlast, reference outputs, counters; shares widened to 64 bit.
- README rewritten with honest limits and reproducible evidence.

### Fixed
- Verilator `EOFNEWLINE` failures.
- Corrupt opcode leaked following header bytes into parsed fields.
- E/C/X share offset regression (byte 19, not 20).
- L participant-state offset (byte 25).
- WebGPU canvas context claimed by a 2D context in the constructor.
- WebGPU `writeBuffer` size semantics.
- MCP BigInt serialization.

### Known limitations
- Multi-frame MoldUDP64 back-to-back flow control.
- No OpenLane/OpenSTA Fmax sign-off.
- RTL top-of-book not implemented (WASM model only).
- npm/PyPI/GHCR not published (build/test only).
