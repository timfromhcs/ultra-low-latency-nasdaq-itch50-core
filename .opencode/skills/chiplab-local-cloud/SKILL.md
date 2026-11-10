---
name: chiplab-local-cloud
description: Run, connect, secure and test the ChipLab local cloud (LAN service, local JSON store, bearer token, web Test/Sync/Pull panel) on a laptop, phone or Docker. Use when asked about local cloud, LAN access, the `.data` store or the EXE service.
---

# ChipLab local cloud

## Start

```bash
# loopback only (default): writes allowed from this machine
node backend/server.mjs

# LAN: phone/tablet on the same network; token required for non-loopback writes
node backend/server.mjs --host 0.0.0.0 --token "long-random-token"

# single EXE
dist\chiplab.exe --host 0.0.0.0 --port 4173 --token "long-random-token"
```

Flags/env: `--host/--port/--token/--data-dir` and `HOST`, `PORT`, `CHIPLAB_TOKEN`,
`CHIPLAB_DATA_DIR`. The startup log prints every LAN URL.

## Connect from the browser

Open the LAN URL, use the **Local cloud** panel: paste the token, press **Test**, then
**Sync** (push browser history) or **Pull** (replace local history with the service's).
Auto-connect only happens when the page is served by `chiplab-local-cloud`; the Vercel
deployment has no cloud endpoint.

## API

| Endpoint | Method | Auth |
|---|---|---|
| `/api/cloud/info` | GET | none |
| `/api/store` | GET | token if set, else loopback |
| `/api/store/:namespace` | GET/PUT/DELETE | same |

PUT body: `{ "data": <json>, "expectedRevision": <n> }`. Conflicts return 409,
payloads over 1 MB return 413, invalid namespaces and traversal return 400.

## Security

- Loopback by default; `0.0.0.0` is an explicit opt-in.
- With `--token`, every store call needs `Authorization: Bearer <token>`.
- Data stays in `.data/` (git-ignored, mode `0o600`, atomic temp+rename).
- Docker: requests arrive from a non-loopback bridge, so set `CHIPLAB_TOKEN`.

## Test

```bash
node scripts/test_cloud_api.mjs
# CLOUD API PASS (auth, revisions, 409, 400, 413, list, delete)
```

## Pitfalls

- Do not cache `/api/*` in the service worker (stale 404s).
- A LAN URL is only reachable if the host firewall allows the port.
- The EXE is unsigned (no Authenticode); verify the release SHA-256 and the SLSA
  attestation (`gh attestation verify chiplab.exe --repo timfromhcs/ultra-low-latency-nasdaq-itch50-core`).
