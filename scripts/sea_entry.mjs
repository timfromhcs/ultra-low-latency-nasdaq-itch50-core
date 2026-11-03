// =============================================================================
// File: scripts/sea_entry.mjs
// Description: Entry point bundled into dist/chiplab.exe (Node SEA).
//              Embeds the web app + WASM, serves the same local API, and opens
//              the browser. This is a single-file distribution of the demo.
// =============================================================================
import http from "node:http";
import { exec } from "node:child_process";
import { ASSETS } from "../dist/web_assets.generated.mjs";
import { loadCoreFromBytes, CHIPS, decodeRecord, hostInfo, countRecordErrors } from "../backend/wasm.mjs";

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".wasm": "application/wasm", ".wgsl": "text/plain; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".webmanifest": "application/manifest+json",
};

const args = process.argv.slice(2);
const getArg = (name, dflt) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
};
const PORT = Number(getArg("port", process.env.PORT || 4190));
const HOST = getArg("host", "127.0.0.1");
const NO_OPEN = args.includes("--no-open");
const PROBE = args.includes("--probe");

async function boot() {
const files = new Map();
for (const [name, b64] of Object.entries(ASSETS)) files.set(name, Buffer.from(b64, "base64"));
const wasm = files.get("wasm/chiplab_core.wasm");
if (!wasm) { console.error("embedded WASM missing"); process.exit(1); }
const core = await loadCoreFromBytes(wasm);
const host = hostInfo();

function json(res, code, obj) {
  const body = JSON.stringify(obj, (_k, v) => (typeof v === "bigint" ? v.toString() : v));
  res.writeHead(code, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(body), "cache-control": "no-store", "access-control-allow-origin": "*" });
  res.end(body);
}
function summarize(h, streamBytes) {
  const cycles = Math.max(1, h.cycles), ns = cycles * 3.1;
  return { chip: h.chip, messages: h.count, cycles, ns, gbps: (h.bytesIn * 8) / (ns * 1e-9) / 1e9, mps: h.count / (ns * 1e-9) / 1e6, bytesIn: h.bytesIn, streamBytes, corrupt: h.corrupt, frames: h.frames };
}
function runBody(body = {}) {
  const count = Math.max(1, Math.min(2_000_000, Number(body.count) || 100000));
  const chip = Math.max(0, Math.min(7, Number(body.chip ?? 1)));
  const seed = Math.max(0, Number(body.seed) || 1337);
  const mode = Math.max(0, Math.min(2, Number(body.mode) || 0));
  const stream = core.generate(count, mode, seed);
  const r = core.run(chip, stream);
  const records = [];
  for (let i = 0, off = 0; i < 60 && off + 80 <= r.records.length; i++, off += 80) records.push(decodeRecord(r.records, off));
  const book = core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 48);
  const errors = chip === 0 ? 0 : countRecordErrors(core.run(0, stream), r);
  return { ok: true, ...summarize(r.header, stream.len), errors, seed, mode, book, records, host };
}

if (PROBE) {
  console.log(JSON.stringify({ host, wasm: { bytes: wasm.length, version: core.version() }, chips: CHIPS.length }, null, 2));
  exec("wmic path win32_VideoController get name", (e, out) => {
    if (!e && out) console.log(out.trim());
    process.exit(0);
  });
} else {
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    try {
      if (req.method === "OPTIONS") {
        res.writeHead(204, { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,OPTIONS", "access-control-allow-headers": "content-type" });
        return res.end();
      }
      if (url.pathname === "/api/health") return json(res, 200, { ok: true, service: "chiplab-sea", wasm: { version: core.version(), bytes: wasm.length }, chips: CHIPS, host, upstream: "local" });
      if (url.pathname === "/api/chips") return json(res, 200, { ok: true, chips: CHIPS });
      if (url.pathname === "/api/run" && req.method === "POST") {
        let buf = "";
        for await (const c of req) buf += c;
        return json(res, 200, runBody(buf ? JSON.parse(buf) : {}));
      }
      if (url.pathname === "/api/compare" && req.method === "POST") {
        let buf = "";
        for await (const c of req) buf += c;
        const body = buf ? JSON.parse(buf) : {};
        const count = Math.max(1, Math.min(1_000_000, Number(body.count) || 100000));
        const stream = core.generate(count, 0, Math.max(0, Number(body.seed) || 1337));
        return json(res, 200, { ok: true, rows: core.compare(stream), host, chips: CHIPS });
      }
      if (url.pathname === "/api/book" && req.method === "POST") {
        let buf = "";
        for await (const c of req) buf += c;
        const body = buf ? JSON.parse(buf) : {};
        const count = Math.max(1, Math.min(1_000_000, Number(body.count) || 100000));
        const stream = core.generate(count, 0, Math.max(0, Number(body.seed) || 1337));
        return json(res, 200, { ok: true, book: core.buildBook(stream) });
      }
      let rel = decodeURIComponent(url.pathname);
      if (rel === "/" || rel === "") rel = "index.html";
      rel = rel.replace(/^\/+/, "");
      const data = files.get(rel);
      if (!data) return json(res, 404, { ok: false, error: "not found", path: rel });
      const ext = "." + (rel.split(".").pop() || "");
      res.writeHead(200, { "content-type": MIME[ext] || "application/octet-stream", "content-length": data.length, "cache-control": ext === ".wasm" ? "public, max-age=3600" : "no-store" });
      res.end(data);
    } catch (err) {
      json(res, 500, { ok: false, error: String(err?.stack || err) });
    }
  });
  server.listen(PORT, HOST, () => {
    console.log(`ChipLab single EXE listening on http://${HOST}:${PORT}`);
    console.log(`  embedded files: ${files.size}, WASM: ${wasm.length} bytes, chips: ${CHIPS.length}`);
    if (!NO_OPEN) {
      const url = `http://${HOST}:${PORT}/`;
      if (process.platform === "win32") exec(`cmd /c start "" "${url}"`);
      else if (process.platform === "darwin") exec(`open "${url}"`);
      else exec(`xdg-open "${url}"`);
    }
  });
}
}

boot().catch((err) => { console.error(err); process.exit(1); });
