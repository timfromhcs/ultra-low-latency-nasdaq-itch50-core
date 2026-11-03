# API reference

ChipLab exposes one engine through four surfaces: HTTP/JSON (local server and EXE),
MCP tools (agents), the npm package (Node), and the Python package. All of them run
the same deterministic stream generator and golden parser.

---

## 1. HTTP API

Start the service:

```bash
node backend/server.mjs                      # http://127.0.0.1:8787, loopback only
node backend/server.mjs --host 0.0.0.0       # LAN
node backend/server.mjs --token secret       # bearer token required for /api/store
```

`dist\chiplab.exe` accepts the same flags (`--host`, `--port`, `--token`, `--data-dir`).

### `GET /api/health`

```json
{
  "ok": true,
  "service": "chiplab",
  "version": "0.3.1",
  "wasm": { "version": 196865, "bytes": 51234 },
  "chips": [ { "id": 1, "key": "rtl-1c", "name": "ITCH-50 v2" } ],
  "host": { },
  "upstream": "local",
  "cloud": { "tokenRequired": false, "persistence": "local-json" }
}
```

### `GET /api/cloud/info`

No authentication. Returns version, host, LAN URLs, token state, data directory,
uptime and namespace names. Never starts a server or writes state.

### `GET|PUT|DELETE /api/store/:namespace`

Local JSON persistence with revisions. `:namespace` is `[A-Za-z0-9_-]{1,32}`.

| Method | Body | Result |
|---|---|---|
| `GET` | — | `{ok, namespace, revision, updatedAt, data}`; 404 if absent |
| `PUT`/`POST` | `{data, expectedRevision}` | 200 with new revision; 409 on revision mismatch; 413 above 1 MB |
| `DELETE` | — | 200 `{ok:true}`; 404 if absent |

Auth: bearer token if `--token` is set; otherwise loopback only. Cross-origin access is
limited to the headers the web UI needs.

### `GET /api/chips`

The chip model catalog used by the web UI (id, key, name, family, latency).

### `POST /api/run`, `POST /api/compare`, `POST /api/book`

Deterministic simulation endpoints used by the UI and MCP server.

```json
{ "chip": 1, "count": 100000, "seed": 1337, "mode": 0 }
```

- `chip`: 0–7 (`0` scalar golden, `1` RTL 1-cycle, `2` safe 2-cycle, `3`/`4` rival
  models, `5` intentionally lossy, `6` Mold front-end, `7` parser+book).
- `count`: 1–1,000,000 for compare/book; run accepts up to 2,000,000.
- `mode`: 0 raw ITCH, 1 MoldUDP64, 2 Ethernet+Mold.

Responses carry a header summary, sample 80-byte records (decoded) and, for
`/api/book`, the top-of-book table.

### Errors

All errors are JSON: `{ok:false, error:"..."}` with 400 (bad input), 401
(unauthorized), 404, 409 (revision conflict), 413 (too large), 500.

---

## 2. MCP server

```bash
node mcp/server.mjs        # stdio transport
```

Twelve read-only tools with strict schemas and a hashed audit log (`mcp/SECURITY.md`):

| Tool | Arguments | Returns |
|---|---|---|
| `chiplab.chips` | — | chip catalog |
| `chiplab.run` | `chip`, `count`, `seed`, `mode` | summary, sample records, BBO |
| `chiplab.compare` | `count`, `seed` | per-chip PASS/FAIL table |
| `chiplab.book` | `count`, `seed` | top-of-book table |
| `chiplab.formal_status` | — | `reports/formal.json` |
| `chiplab.health` | — | service/version/WASM/host/evidence |
| `chiplab.cloud_info` | — | data dir, namespaces, token state |
| `chiplab.history` | — | revision, run count, last summary (no payloads) |
| `chiplab.release_status` | — | version/changelog/artifact checks |
| `chiplab.sbom` | — | component count and scopes |
| `chiplab.synth_status` | — | last cell count per width |
| `chiplab.docs` | `doc` (enum) | one documentation file |

`chiplab.docs` serves a fixed catalog — never an arbitrary path:
`architecture`, `benchmarks`, `datasheet`, `integration-guide`, `errata`, `api`,
`long-term-plan`, `release-plan`, `mold-backpressure`, `mcp-security`, `readme`,
`changelog`.

---

## 3. npm package

```bash
npm install ./chiplab-core-0.3.1.tgz     # or from the GitHub release
```

The package name is `@chiplab/core` (the release tarball is `chiplab-core-0.3.1.tgz`).

```js
import { RECORD_SIZE, CHIPS, chipById, decodeHeader, decodeRecord }
  from "@chiplab/core";
```

Constants: `RECORD_SIZE = 80`, `HEADER_SIZE = 48`, `MAGIC = 0x42414c43`
("CLAB" little-endian), `CHIPS`.

```js
const h = decodeHeader(bytes);          // {magic, chip, count, cycles, bytesIn, corrupt, frames}
const rec = decodeRecord(bytes, 48);    // one 80-byte field record
```

CLI: `npx chiplab --count 10000 --chip 1` prints the run summary and five decoded
records; `npx chiplab --compare` prints the per-model table.

---

## 4. Python package

```bash
pip install ./chiplab_itch-0.3.1-py3-none-any.whl
```

```python
from chiplab_itch import (
    parse_stream, parse_one, generate_stream, generate_vectors,
    records_bytes, Record, RECORD_SIZE,
)

records = parse_stream(open("stream.bin", "rb").read())   # list[Record]
blob = generate_stream(count=1000, seed=1337)              # deterministic ITCH bytes
```

`Record` exposes every protocol field plus `payload` and `raw`; `records_bytes`
serialises to the 80-byte layout the RTL and WASM emit. CLI:

```bash
python -m chiplab_itch generate --count 1000 --out vectors   # stream.bin + expected.bin
python -m chiplab_itch parse --file stream.bin --limit 20    # JSONL
python -m chiplab_itch selfcheck                             # all opcodes
```

Version check: `chiplab_itch.__version__ == "0.3.1"`.

---

## 5. Hardware API

The RTL interface (AXI4-Stream ingress, registered 80-byte record egress, BBO event
stream, status and performance counters) is documented in `datasheet.md` and
`integration-guide.md`. Performance counters are exported as:

```systemverilog
output [31:0] metrics_msg_count, metrics_byte_count,
              metrics_gap_count, metrics_drop_count, metrics_cycle_count;
output [7:0]  metrics_occupancy_max;
output [31:0] metrics_hist0 /* .. hist7 */;
```

Derived rates: `messages/s = Δmsg_count × f_clk / Δcycle_count`.
