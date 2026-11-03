// =============================================================================
// File: backend/server.mjs
// Description: Local-first ChipLab backend. Serves the WebGPU demo and exposes
//              the same WASM chip models that the browser runs.
//
//   node backend/server.mjs            # http://127.0.0.1:4173
//   PORT=8081 node backend/server.mjs
//
// No npm dependencies. Node 22+.
// =============================================================================
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadCore, CHIPS, decodeRecord, hostInfo, countRecordErrors } from "./wasm.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const webDir = path.resolve(root, "web");
const PORT = Number(process.env.PORT || 4173);
const HOST = process.env.HOST || "127.0.0.1";

const core = await loadCore();
const host = hostInfo();

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".wasm": "application/wasm",
  ".wgsl": "text/plain; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
};

function json(res, code, obj) {
  const body = JSON.stringify(obj, (_k, v) => (typeof v === "bigint" ? v.toString() : v));
  res.writeHead(code, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
  });
  res.end(body);
}

function readBody(req, limit = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) { reject(new Error("body too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {}); }
      catch (e) { reject(e); }
    });
    req.on("error", reject);
  });
}

function clampInt(v, lo, hi, dflt) {
  const n = Number(v);
  if (!Number.isFinite(n)) return dflt;
  return Math.max(lo, Math.min(hi, Math.trunc(n)));
}

function summarize(header, rows) {
  const cycles = Math.max(1, header.cycles);
  const ns = cycles * 3.1;
  return {
    chip: header.chip,
    messages: header.count,
    cycles,
    ns,
    gbps: (header.bytesIn * 8) / (ns * 1e-9) / 1e9,
    mps: header.count / (ns * 1e-9) / 1e6,
    bytesIn: header.bytesIn,
    corrupt: header.corrupt,
    frames: header.frames,
    rows,
  };
}

async function apiRun(body) {
  const count = clampInt(body.count, 1, 2_000_000, 100_000);
  const chip = clampInt(body.chip, 0, 7, 1);
  const seed = clampInt(body.seed, 0, 2 ** 31 - 1, 1337);
  const mode = clampInt(body.mode, 0, 2, 0);
  const sample = clampInt(body.sample, 0, 500, 80);
  const t0 = performance.now();
  const stream = core.generate(count, mode, seed);
  const result = core.run(chip, stream);
  const book = core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 48);
  const records = [];
  for (let i = 0, off = 0; i < sample && off + 80 <= result.records.length; i++, off += 80) {
    records.push(decodeRecord(result.records, off));
  }
  const wall = performance.now() - t0;
  const errors = chip === 0 ? 0 : countRecordErrors(core.run(0, stream), result);
  return {
    ok: true,
    mode,
    seed,
    streamBytes: stream.len,
    wallMs: wall,
    errors,
    ...summarize(result.header, records),
    book,
    host,
    wasm: { version: core.version(), bytes: core.wasmBytes },
  };
}

function apiCompare(body) {
  const count = clampInt(body.count, 1, 1_000_000, 100_000);
  const seed = clampInt(body.seed, 0, 2 ** 31 - 1, 1337);
  const t0 = performance.now();
  const stream = core.generate(count, 0, seed);
  const rows = core.compare(stream);
  return { ok: true, seed, streamBytes: stream.len, wallMs: performance.now() - t0, rows, host, chips: CHIPS };
}

function apiBook(body) {
  const count = clampInt(body.count, 1, 1_000_000, 100_000);
  const seed = clampInt(body.seed, 0, 2 ** 31 - 1, 1337);
  const stream = core.generate(count, 0, seed);
  const book = core.buildBook(stream);
  return { ok: true, streamBytes: stream.len, book };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  try {
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET,POST,OPTIONS",
        "access-control-allow-headers": "content-type",
      });
      return res.end();
    }

    if (url.pathname === "/api/health") {
      return json(res, 200, {
        ok: true,
        service: "chiplab",
        wasm: { version: core.version(), bytes: core.wasmBytes },
        chips: CHIPS,
        host,
        upstream: "local",
      });
    }
    if (url.pathname === "/api/chips") {
      return json(res, 200, { ok: true, chips: CHIPS });
    }
    if (url.pathname === "/api/run" && req.method === "POST") {
      return json(res, 200, await apiRun(await readBody(req)));
    }
    if (url.pathname === "/api/compare" && req.method === "POST") {
      return json(res, 200, apiCompare(await readBody(req)));
    }
    if (url.pathname === "/api/book" && req.method === "POST") {
      return json(res, 200, apiBook(await readBody(req)));
    }

    // Static files
    let rel = decodeURIComponent(url.pathname);
    if (rel === "/" || rel === "") rel = "/index.html";
    const file = path.resolve(webDir, "." + rel);
    if (!file.startsWith(webDir)) return json(res, 403, { ok: false, error: "forbidden" });
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      return json(res, 404, { ok: false, error: "not found", path: rel });
    }
    const ext = path.extname(file).toLowerCase();
    const data = fs.readFileSync(file);
    res.writeHead(200, {
      "content-type": MIME[ext] || "application/octet-stream",
      "content-length": data.length,
      "cache-control": ext === ".wasm" ? "public, max-age=3600" : "no-store",
    });
    res.end(data);
  } catch (err) {
    json(res, 500, { ok: false, error: String(err && err.stack || err) });
  }
});

server.listen(PORT, HOST, () => {
  const line = `ChipLab backend listening on http://${HOST}:${PORT}`;
  console.log(line);
  console.log(`  wasm: ${core.wasmBytes} bytes, version 0x${core.version().toString(16)}`);
  console.log(`  chips: ${CHIPS.length}, host: ${host.cpu} / ${host.cores} cores / ${host.memoryGb} GB`);
});
