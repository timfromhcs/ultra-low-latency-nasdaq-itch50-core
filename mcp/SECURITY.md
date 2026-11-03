# MCP security notes

This server is a **local stdio** process. It is not an HTTP service and has no
authentication layer; do not expose it through a network proxy without adding one.

## Least privilege

The tools are read-only computations over a deterministic stream, plus read-only
access to committed evidence files:

| Tool | Inputs | Access |
|---|---|---|
| `chiplab.chips` | none | static registry |
| `chiplab.run` | chip, count, seed, mode | WASM only |
| `chiplab.compare` | count, seed | WASM only |
| `chiplab.book` | count, seed | WASM only |
| `chiplab.formal_status` | none | reads `reports/formal.json` |
| `chiplab.health` | none | static + report existence |
| `chiplab.cloud_info` | none | lists `.data` namespaces |
| `chiplab.history` | none | reads `.data/default.json` summary |
| `chiplab.release_status` | none | version/report consistency |
| `chiplab.sbom` | none | reads `reports/sbom.json` |
| `chiplab.synth_status` | none | parses `reports/synth_*.log` |
| `chiplab.docs` | doc (fixed enum) | reads one catalogued doc |

There is **no shell, filesystem write, network, environment or arbitrary file tool**.
`chiplab.docs` accepts only twelve fixed keys; any other string is rejected.
Counts are capped at 2,000,000; seeds/chips/modes are range-checked; unknown arguments
are rejected.

## Tool poisoning / prompt injection

- Tool descriptions are static in `server.mjs`; review them like code.
- Tool results contain synthetic market data only. They do not contain instructions.
- The server never reads a user-supplied file path or URL.
- Audit every call to `reports/mcp-audit.log` with a hashed argument set (no raw values).

## Deployment

- Run as an unprivileged user, stdio only.
- If you wrap it in HTTP, terminate TLS, authenticate, rate-limit, and allowlist tools.
- Pin the Node version and install from the repository lockfile.
- Treat updates as code review: a changed tool description is a security-relevant change.

## Verification

```bash
node mcp/client_smoke.mjs
# invalid args must be rejected:
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"chiplab.run","arguments":{"count":99999999}}}' | node mcp/server.mjs
```
