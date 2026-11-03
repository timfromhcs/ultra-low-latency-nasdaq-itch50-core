# Stable Release Plan — v0.3.0 "Local Cloud"

> Status: **ACTIVE — executed in this session**
> Target: first stable, reproducible release of ChipLab for **local cloud + web + EXE + GitHub**
> Previous plans: `LONG_TERM_PLAN.md`, `AUTONOMOUS_PLAN_V2.md`, `AUTONOMOUS_PLAN_V1.md`
> Live web: <https://chiplab-ten.vercel.app/>
> Rule: **no release claim without a green gate and a checksummed artifact.**

---

## 1. Release definition

**v0.3.0** is the first release that a user can install and use without a developer:

1. **Local cloud** — a LAN-accessible local Node/EXE service with local persistence,
   a device name, a health endpoint and an optional bearer token.
2. **Web** — the same PWA works locally, on a phone over LAN, and on Vercel;
   data stays in the browser or on the user's local service.
3. **EXE** — `chiplab.exe` starts the local cloud and the web UI from one file.
4. **GitHub** — tag-driven release with EXE, Docker digest, npm tarball, Python wheel,
   SBOM and SHA-256 checksums; no secrets in the repo.
5. **MCP** — every ChipLab capability exposed as a read-only/limited MCP tool.
6. **README** — install matrix, local-cloud guide, evidence, honest limits, release notes.
7. **Design** — Telemetry-based dense tool; mobile 390 px, desktop 1440 px; reviewed copy.

**v1.0.0 is deliberately not claimed.** It is reserved for: multi-frame MoldUDP64
back-pressure, RTL top-of-book, LibreLane timing/DRC/LVS sign-off, and a published
package/image set with provenance.

---

## 2. Current audit (2026-11-03)

| Area | State | Gap for v0.3.0 |
|---|---|---|
| CI | green (run #24) | release workflow missing |
| Versions | root/npm/native/pyproject 0.2.0, wasm-core 0.1.0 | unify to 0.3.0 |
| Backend | stateless `/api/*` | no persistence, no LAN auth, no cloud info |
| Web | local/Vercel, OPFS history | no local-cloud connect/sync UI |
| EXE | embeds web + WASM, port/no-open/probe | no `--host 0.0.0.0`, `--token`, `--data-dir` |
| MCP | 5 tools | no release/SBOM/synth/store/history tools |
| GitHub | CI, Docker, EXE workflows | no tagged GitHub Release, no checksums |
| npm/PyPI | build/test only | no trusted-publishing release job |
| README | good technical docs | no stable-release section / install matrix for local cloud |
| Design | dense lab UI, WebGPU | no local-cloud status/settings panel; copy review pending |

---

## 3. Research: release best practices (2026)

| Topic | Finding | Decision |
|---|---|---|
| SemVer | Once published, contents of a version must not change; breaking changes need a major. | 0.3.0 is additive; 1.0.0 only after the hard gates. |
| Changelog | Keep a Changelog format; release notes generated from it. | `CHANGELOG.md` is the source of release notes. |
| GitHub Releases | Tags + assets + release notes; artifacts should be checksummed. | `release.yml` on `v*` uploads EXE, Docker digest, sbom, checksums. |
| npm | Trusted Publishing/OIDC and staged publishing are the safe path; provenance links source + build. | Add OIDC publish job, `--provenance`, no long-lived token required if configured. |
| PyPI | Trusted Publishing via OIDC is preferred; build sdist+wheel. | Add `pypi-publish` job with `id-token: write`, `pypi` environment. |
| Docker | GHCR image with digest and provenance/attestations. | Keep `docker/build-push-action` with `provenance: true`, record digest. |
| SBOM / SLSA | CycloneDX SBOM and build provenance raise supply-chain confidence. | SBOM in every release; GitHub artifact attestation where available. |
| EXE | Single-file Node SEA is convenient but unsigned; signing is required for trust. | Ship checksum + optional Authenticode instructions; do not claim signed. |
| Local-first cloud | LAN service + local persistence + optional token is the smallest useful "cloud"; no cloud account. | Implement `backend/store.mjs`, `/api/cloud/*`, `/api/store/*`; default loopback, opt-in LAN. |
| MCP security | Least privilege, static tool descriptions, strict schemas, audit, no shell/file tools. | Extend the 5 tools; all inputs range-checked; audit hashes; local store read-only. |
| PWA | Installable manifest, offline shell, service worker, budgets. | Keep; add local-cloud status, test 390/1440. |

Sources: semver.org, keepachangelog.com, GitHub Releases docs, npm Trusted Publishing
(2026), PyPI Trusted Publishing, SLSA 1.0, Docker attestations, MCP security best practices.

---

## 4. Target architecture

```
┌─────────────────────────── user hardware ───────────────────────────┐
│  chiplab.exe / node backend/server.mjs                               │
│   ├── static web (same files as Vercel)                              │
│   ├── /api/run, /api/compare, /api/book  (WASM, stateless)           │
│   ├── /api/cloud/info, /api/cloud/qr      (LAN URL, token state)     │
│   └── /api/store/<namespace>              (local JSON, atomic writes)│
│                                                                      │
│  Browser (phone/desktop)                                             │
│   ├── OPFS/IndexedDB local history                                   │
│   ├── optional "Local Cloud" URL + token                             │
│   └── WebGPU compute / Canvas2D fallback                             │
└──────────────────────────────────────────────────────────────────────┘
        │ tag v0.3.0
        ▼
GitHub Release: EXE + npm tgz + wheel + sdist + SBOM + checksums + Docker digest
        │
        ▼
Vercel (static + stateless API) · GHCR image · npm/PyPI (trusted publishing)
```

**Data rule:** local cloud stores only the user's own runs/settings under `.data/`,
never uploaded by default. Vercel has no database and no user data.

---

## 5. Release loop (execute until all gates pass)

```text
for attempt in 1..N:
  0. sync versions (root/npm/native/pyproject/wasm-core) and rebuild WASM
  1. fast gate: node scripts/gate.mjs
  2. local-cloud gate: start server, store round-trip, token rejection
  3. web gate: 390/1440, local-cloud connect, WebGPU/Canvas2D
  4. MCP gate: all tools + invalid args + audit
  5. EXE gate: build, start, /api/cloud/info, store round-trip
  6. package gate: npm pack, wheel, clean installs
  7. Docker gate: build + health
  8. release gate: tag dry-run, checksums, SBOM, changelog
  9. docs gate: README links, version mentions, no stale claims
  if any gate fails: classify, minimal fix, rerun only that gate
```

**Stop conditions:** all gates green + `git status` clean + tag `v0.3.0` created locally
(push only with user approval).

---

## 6. Work breakdown

### P0 — Version and release plumbing
- [x] `scripts/version.mjs` reads/writes one version across package.json, npm, native,
      pyproject, wasm-core, MCP serverInfo and SBOM metadata.
- [x] Unify 0.3.0; rebuild WASM (`version() = 0x000300`, UI prints `major.minor.patch`).
- [x] `scripts/release_check.mjs`: version/changelog/README/SBOM/artifact consistency.
- [x] `CHANGELOG.md` 0.3.0 (Keep a Changelog).

### P1 — Local cloud backend
- [x] `backend/store.mjs`: atomic JSON read/write, namespace allowlist, 1 MB limit,
      revision conflict, delete.
- [x] `/api/cloud/info`: version, host, LAN addresses, token enabled, data dir, uptime.
- [x] `/api/store/:ns`: GET/PUT/DELETE with bearer token or loopback.
- [x] CLI/env: `--host`, `--port`, `--token`, `--data-dir` for server **and** EXE.
- [x] Loopback by default; `0.0.0.0` opt-in; CORS limited to needed headers.
- [x] `scripts/test_cloud_api.mjs`: 401, revision 1→2, 409, 400 traversal, 413 oversize,
      list, delete — wired into the gate.

### P2 — Web local-cloud panel
- [x] "Local cloud" panel: URL, token (password field), Test, Sync, Pull.
- [x] Status badge: connected / not connected, endpoint, LAN URL, token state, namespaces.
- [x] Uses the backend store when connected; falls back to OPFS otherwise.
- [x] Auto-connects only when the page is served by `chiplab-local-cloud`.
- [x] Service worker never caches `/api/*` (fixed a stale-404 bug found in testing).
- [x] Mobile 390 px and desktop 1440 px: no horizontal overflow
      (`reports/web-390-cloud.png`, `reports/web-1440-cloud.png`).

### P3 — MCP expansion
- [x] Added `chiplab.health`, `chiplab.cloud_info`, `chiplab.history`,
      `chiplab.release_status`, `chiplab.sbom`, `chiplab.synth_status`, `chiplab.docs`.
- [x] Strict schemas; `chiplab.docs` accepts a fixed 8-key catalog; no arbitrary paths.
- [x] `mcp/SECURITY.md` updated; smoke covers all tools and rejects `.docs` traversal.

### P4 — GitHub release
- [x] `release.yml`: tag `v*` → verify, Windows EXE, npm/PyPI packages, SBOM,
      `SHA256SUMS.txt`, GitHub Release.
- [x] `scripts/checksums.mjs` and `release_check.mjs`.
- [x] Release notes generated from `CHANGELOG.md`.
- [x] Docker image builds and serves health + cloud info; writes need `CHIPLAB_TOKEN`.
- [ ] npm/PyPI **publishing** (trusted publishing) — prepared but requires repo/OIDC setup.
- [ ] Tag `v0.3.0` push (local tag created; push with approval).

### P5 — README / guides / SEO
- [x] "Stable v0.3.0 — Local Cloud" section, install matrix, local-cloud API,
      security model, versioning/release artifacts.
- [x] Version references cleaned (0.2.0 → 0.3.0).
- EN/DE/FR guides updated with local cloud, Docker token and 12 MCP tools (EN fully;
  DE/FR carry the same structure and will be re-synced in the next docs pass).
- [x] Honest limits retained; no 1.0.0 claim.
- [x] Three project skills added under `.opencode/skills/`: `chiplab-verify`,
      `chiplab-local-cloud`, `chiplab-release`.

---

## 7. Acceptance criteria (v0.3.0)

- [x] `node scripts/gate.mjs` → 100 % (10 checks, including cloud-api and release-check).
- [x] Local cloud: GET/PUT `/api/store/default`, revision increments, token required
      for non-loopback writes, 413 on >1 MB, path traversal rejected.
- [x] Web: 100k run, 0 errors, WebGPU, cloud Test/Sync/Pull round-trip, 390/1440.
- [x] MCP: 12 tools, invalid args and `.docs` traversal rejected, audit entries, smoke pass.
- [x] EXE: 0.3.0, `--host/--token/--data-dir`, `/api/cloud/info`, store round-trip, 401 without token.
- [x] npm tarball + Python wheel install from clean dirs (`npm pkg ok`, `selfcheck OK`).
- [x] Docker `/api/health` + `/api/cloud/info` + store with `CHIPLAB_TOKEN`.
- [x] GitHub workflow files parse as YAML; release job stages all artifacts.
- [x] README version/changelog/links consistent; release_check 10/10.
- [x] `git status` clean; tag `v0.3.0` created (local) and pushed with approval.
- [x] GitHub Release published with 6 assets:
      <https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core/releases/tag/v0.3.0>

## 8. Release outcome (2026-11-03)

- Tag `v0.3.0` on commit `b414be1`; `Release` workflow run 41594730252: **success**
  (verify, Windows EXE, packages, SBOM/checksums/publish).
- Assets: `chiplab.exe` (83.7 MB), `chiplab-core-0.3.0.tgz`, `chiplab_itch-0.3.0` wheel +
  sdist, `sbom.json`, `SHA256SUMS.txt`.
- Vercel production deployment for `b414be1`: **READY** (auto-deploy from `main`).
- Docker image built locally and verified (health, cloud info, token-gated writes).
- Remaining for a future 0.3.x/0.4.0: multi-frame Mold back-pressure, RTL top-of-book,
  LibreLane/OpenSTA sign-off, npm/PyPI trusted publishing, bit-reproducible builds.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| LAN service exposes data | loopback default; token required for non-loopback writes; no directory browsing |
| Local store corruption | atomic temp+rename, revision check, size cap |
| npm/PyPI publish blocked (2026 rules) | trusted publishing docs + manual approval; build-only until configured |
| EXE unsigned | checksum + Authenticode instructions; no "signed" claim |
| WebGPU unavailable | Canvas2D fallback; local cloud works without GPU |
| Scope creep into 1.0.0 | hard gate: R1 + BBO + LibreLane before 1.0.0 |

## 9. Patch release: v0.3.1

The published 0.3.0 Python wheel reported `chiplab_itch.__version__ == "0.2.0"` even
though the distribution metadata was 0.3.0. SemVer allows a patch release; assets of
a published version must not be changed in place.


- `scripts/version.mjs` now also syncs `package-lock.json` and the Python `__version__`.
- `scripts/sbom.mjs` reads the WASM version from package.json.
- `scripts/release_check.mjs` checks both new version fields (14 checks).
- README encoding restored; Vercel cloud probe uses `/api/health` first (no 404).
- `docker-compose.yml` uses 0.3.1, supports `CHIPLAB_TOKEN` and a persistent data volume.
- WASM ABI rebuilt to 0x000301; EXE, npm tarball and Python wheel/sdist rebuilt.
- Tag `v0.3.1` publishes the same six-asset set through the `Release` workflow.
