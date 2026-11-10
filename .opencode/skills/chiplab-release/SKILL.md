---
name: chiplab-release
description: Cut a ChipLab release correctly — bump one version, rebuild artifacts, run the gate, update CHANGELOG/README, create a tag and let the Release workflow publish EXE/npm/PyPI/SBOM/checksums. Use when asked to release, bump the version, tag, or prepare GitHub assets.
---

# Cut a ChipLab release

## 1. Bump the one version

```bash
node scripts/version.mjs --set 0.4.0
```

This updates `package.json`, `packages/npm/package.json`, `native/Cargo.toml`,
`wasm-core/Cargo.toml`, `packages/python/pyproject.toml`, the WASM ABI version,
`mcp/server.mjs`, `api/_core.mjs` and `scripts/sbom.mjs`.

## 2. Rebuild the WASM (ABI + web + npm copies)

```bash
npm run build:wasm
cp wasm-core/target/wasm32-unknown-unknown/release/chiplab_core.wasm web/wasm/
cp web/wasm/chiplab_core.wasm packages/npm/wasm/
```

`version()` is `(major<<16)|(minor<<8)|patch`; the UI prints all three parts.

## 3. Update docs, then gate

- `CHANGELOG.md`: new `## X.Y.Z — date` section (Keep a Changelog). This becomes the
  GitHub release notes.
- `README.md`: version references and any changed behavior.
- `reports/sbom.json`: `node scripts/sbom.mjs` (regenerate).

```bash
node scripts/gate.mjs --deep      # must be 100%
node scripts/release_check.mjs    # version/changelog/README/SBOM/artifacts
```

## 4. Build the artifacts locally (optional pre-check)

```bash
npm run build:exe
cd packages/npm && npm pack
cd packages/python && python -m build
```

## 5. Tag and publish

```bash
git add -A && git commit -m "release: vX.Y.Z"
git tag -a vX.Y.Z -m "ChipLab vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

The `Release` workflow runs: verify → Windows EXE → npm/PyPI packages → SBOM →
`SHA256SUMS.txt` → cosign blob signatures → GitHub Release. Confirm all jobs are green
and the release has the six assets plus the `*.sigstore.json` bundles.

## 6. After the release

- Verify Vercel production is READY for the commit.
- Keep `v1.0.0` blocked until parser P&R/DRC/LVS sign-off exists (multi-frame
  back-pressure, A/B recovery and the RTL top-of-book are done).
- The EXE is not Authenticode-signed (SLSA attestation only). npm/PyPI registry
  publishing is opt-in and has not been run. WASM/Python/EXE builds are reproducible:
  `make repro-wasm`, `make repro-python`, `node scripts/repro_exe.mjs`.
