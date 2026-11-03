# Changelog

All notable changes to ChipLab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.0 — 2026-11-03

**First stable release: "Local Cloud".** Installable and usable without a developer:
local LAN service, same web app locally and on Vercel, one EXE, tag-driven GitHub
release with checksums and SBOM, and an expanded read-only MCP surface.

### Added
- **Local cloud service**: `backend/store.mjs` atomic JSON store (namespace allowlist,
  1 MB cap, revision conflict detection, temp-file + rename, `0o600` mode).
- `/api/cloud/info` (version, LAN URLs, token state, data dir, uptime, namespaces) and
  `/api/store` + `/api/store/:namespace` GET/PUT/DELETE with optional bearer token.
- Server CLI: `--host`, `--port`, `--token`, `--data-dir` (plus `HOST`, `PORT`,
  `CHIPLAB_TOKEN`, `CHIPLAB_DATA_DIR`).
- **Web local-cloud panel**: URL/token, Test/Sync/Pull, status badge, LAN hint,
  namespaces; auto-connects only when the page is served by the local service.
- **MCP tools** (12 total): `chiplab.health`, `chiplab.cloud_info`, `chiplab.history`,
  `chiplab.release_status`, `chiplab.sbom`, `chiplab.synth_status`, `chiplab.docs`.
  `chiplab.docs` accepts a fixed 8-key catalog only.
- `scripts/version.mjs` (single version source) and `scripts/release_check.mjs`
  (version/artifact/changelog consistency gate).
- `STABLE_RELEASE_PLAN.md` and `docs/design/mold-backpressure.md`.

### Changed
- Version unified to **0.3.0** across root, npm, native, WASM, PyPI, MCP and SBOM.
- WASM ABI `version() = 0x000300`; the UI prints `major.minor.patch`.
- MCP serverInfo and SBOM metadata follow the same version.
- Heartbeat prompt now continues the active plan instead of stopping after one tick.

### Fixed
- `pre_trigger_valid` no longer asserts for corrupt/unknown opcodes (formal
  counterexample found by the CI proof).
- `axis_skid_buffer.sv` tested: 200 random beats under random `tready`, no loss.

### Security
- MCP strict argument allowlist, range checks, rejects unknown args, hashed audit log.
- `.data/` is git-ignored; no user data is committed or uploaded.
- Dependabot for npm, Cargo, pip and GitHub Actions.

### Known limitations (deliberate, not hidden)
- Multi-frame MoldUDP64 back-to-back flow control still open (R1); skid buffer exists
  but is not yet wired between front-end and depacketizer.
- No LibreLane/OpenSTA Fmax, DRC or LVS sign-off.
- RTL top-of-book not implemented (WASM model only).
- npm/PyPI/GHCR publishing is prepared but not executed (trusted publishing needs
  repository/organisation setup).
- The Windows EXE is not code-signed.

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
