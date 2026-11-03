# Changelog

All notable changes to ChipLab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed
- **MoldUDP64 multi-frame back-to-back flow control** (`rtl/moldudp64_frontend.sv`,
  `moldudp64_depacketizer.sv`, `moldudp64_pipeline.sv`):
  - `tlast` is held with a back-pressured beat instead of being cleared after one cycle;
  - a presented beat is never dropped without a handshake;
  - `frame_start`/`frame_end` are handshake-qualified;
  - the depacketizer emits its own message-derived `tlast` and discards trailing
    Ethernet padding instead of deadlocking.
- New proof: `tb/test_mold_multi.py` — 5 frames back-to-back (4 valid, 1 gap,
  1 dropped port) → 28 records, 0 mismatches.
- CI/Makefile run the multi-frame cocotb test.

### Added
- `rtl/itch_top_of_book.sv`: locate-indexed best bid/ask, aggregate shares at the best
  level, last trade and volume for A/F/E/C/X/D/U/P/Q.
- `tb/test_book.py`: 400 random events against an independent Python book model →
  0 mismatches; plus a **100-event back-to-back test at 1 event/cycle with no stall**.
- The BBO now keeps a per-locate price-level table (16 bid + 16 ask) and computes the
  best with a 16-way reduction, so a best-price removal no longer triggers a rescan.
- The order lookup is a 4-way set-associative bank (4 compares instead of 256).

### Added
- `scripts/synth_book.sh` + `reports/synth_book.json`: Yosys area estimate for the BBO.
  Reduced 32/4/4 config → **62,017 cells**, 0 memories. Area is not optimized and no
  timing/DRC/LVS sign-off is claimed.
- CI/Makefile run the book cocotb test and lint the module.

### Added
- `rtl/itch_top_book.sv`: end-to-end wrapper (ITCH parser -> BBO). The parser is held
  in reset until the BBO tables are initialised, so no message is lost.
- `tb/test_book_top.py`: **152 raw ITCH messages -> 0 BBO mismatches**; U (replace)
  inherits the original side, matching the protocol.
- CI/Makefile run the parser+BBO cocotb test and lint the wrapper.
- `tools/mutate_book.py`: mutation testing for the parser→BBO path. 9 mutants
  (replace side/slot, cancel, max/min, volume, last, stored side) → **9/9 killed**,
  `reports/mutation_book.json`. Weekly `Formal` workflow runs it; `make mutate-book`.

### Added
- RTL ↔ WASM equivalence: `tb/sim_main.cpp --dump` writes the RTL's canonical records;
  `scripts/rtl_wasm_equiv.mjs` runs the WASM twin on the same `stream.bin` and compares
  every field. **100,000 records, 0 mismatches.** `make equiv` + weekly `equivalence` job.

### Added
- BBO **top-4 depth**: four price levels per side (aggregated shares), published with
  each event; the standalone and parser→BBO tests compare them against the Python model.
  Mutation score stays 9/9.
- **A/B feed arbiter** (`rtl/mold_feed_arbiter.sv`): one 2 KB frame buffer per feed,
  sequence-based selection (prefer A on ties), a 64-cycle redundancy window for the
  single-feed case, loser discard and a gap pulse. Test: 6 frames, selection
  [1,2,3,4,7,8], byte-exact, 1 gap (`tb/test_arbiter.py`).
- **BBO risk checks**: `cfg_max_shares` rejects oversized orders and `cfg_collar`
  rejects prices outside last-trade ± collar (0 disables each); `risk_rejects` counter.
  Rejected adds/replaces never touch the book or the level table.
- **A/B system integration** (`rtl/mold_ab_system.sv`): two Mold Ethernet pipelines
  (independent AXI inputs) feed the frame arbiter; frame sequence/count sidebands added
  to `moldudp64_pipeline`. Test: 2 feeds, 10 records, 1 gap, byte-exact.
- **Mold pipeline downstream back-pressure**: `m_axis_tready` added to the depacketizer
  and pipeline; output beats (data/keep/last) are held until accepted. New test:
  329 bytes under random `tready`, no loss or reordering. The A/B system now stalls the
  pipeline instead of relying on the arbiter buffer being large enough.
- **Sequence recovery** (`rtl/mold_recovery.sv`): in-order accept, missing-range request
  (`req_seq`/`req_count`), replay recovery, timeout resync (`abandon`) and duplicate
  rejection, with counters. Test: 4 accepts, 2 gaps, 1 recovered, 1 abandoned,
  1 duplicate. Wiring it to the arbiter and a replay source is the next step.
- **Arbiter recovery mode** (`recovery_en`): on a gap the arbiter requests the missing
  range, drops the out-of-order frames, accepts the replay in order, and abandons to a
  force-accept on timeout (`req_valid/req_seq/req_count/abandon/requests/abandoned`).
  Test: markers [1,2,3,6], 2 requests, 1 abandon.
- **Multi-gap recovery test**: two loss events (3; 6+7) repaired by replayed ranges →
  markers [1..8], 2 requests, no abandon (`tb/test_arbiter.py`). The test acts as the
  replay source; the hardware request interface is the contract.

## 0.3.1 — 2026-11-03

Patch release: packaging metadata and release-loop fixes. No protocol or API change.

### Fixed
- Python package now reports `chiplab_itch.__version__ = "0.3.1"`; the 0.3.0 wheel
  still contained `0.2.0` inside `__init__.py` even though the distribution metadata
  was 0.3.0.
- `scripts/version.mjs` now also updates `package-lock.json` (root + `packages[""]`)
  and the Python `__version__`, so a single command keeps every version in sync.
- `scripts/sbom.mjs` reads the shipped WASM version from `package.json` instead of a
  hard-coded string.
- `backend/version.mjs` is the single runtime version used by `/api/health` and
  `/api/cloud/info` in both the Node server and the EXE; `scripts/version.mjs` updates it.
- `scripts/release_check.mjs` verifies the Python `__version__` and `package-lock.json`.
- README was double-encoded (UTF-8 → CP1252 → UTF-8) by a PowerShell rewrite; restored
  to correct UTF-8.
- The web app probes `/api/health` before the local-cloud endpoint, so the Vercel
  deployment no longer logs a 404 for `/api/cloud/info`.

### Changed
- `docker-compose.yml` uses `chiplab:0.3.1`, accepts `CHIPLAB_TOKEN`, and mounts a
  persistent `chiplab-data` volume at `/app/.data`.
- WASM ABI `version() = 0x000301`.

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
