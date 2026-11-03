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
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadCore, CHIPS, decodeRecord, hostInfo, countRecordErrors } from "./wasm.mjs";
import { LocalStore, MAX_BYTES } from "./store.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const webDir = path.resolve(root, "web");
const av = process.argv.slice(2);
const cli = (name, fallback) => {
  const i = av.indexOf(`--${name}`);
  return i >= 0 && i + 1 < av.length ? av[i + 1] : fallback;
};
const PORT = Number(cli("port", process.env.PORT || 4173));
const HOST = cli("host", process.env.HOST || "127.0.0.1");
const TOKEN = cli("token", process.env.CHIPLAB_TOKEN || "");
const DATA_DIR = path.resolve(cli("data-dir", process.env.CHIPLAB_DATA_DIR || path.join(root, ".data")));
const store = new LocalStore(DATA_DIR);

const core = await loadCore();
const host = hostInfo();
const startedAt = Date.now();

function lanUrls() {
  const out = [];
  for (const [, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === "IPv4" && !a.internal) out.push(`http://${a.address}:${PORT}`);
    }
  }
  return out;
}

function isLoopback(req) {
  const a = req.socket.remoteAddress || "";
  return a === "127.0.0.1" || a === "::1" || a === "::ffff:127.0.0.1";
}

function authorized(req) {
  if (TOKEN) return (req.headers.authorization || "") === `Bearer ${TOKEN}`;
  return isLoopback(req);
}

function cloudInfo() {
  return {
    ok: true,
    service: "chiplab-local-cloud",
    version: "0.3.0",
    host: HOST,
    port: PORT,
    lanUrls: lanUrls(),
    tokenRequired: Boolean(TOKEN),
    persistence: "local-json",
    dataDir: path.basename(DATA_DIR),
    uptimeSec: Math.round((Date.now() - startedAt) / 1000),
    namespaces: store.list(),
    hostInfo: host,
  };
}

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
    let tooBig = false;
    const chunks = [];
    req.on("data", (c) => {
      if (tooBig) return;
      size += c.length;
      if (size > limit) { tooBig = true; chunks.length = 0; return; }
      chunks.push(c);
    });
    req.on("end", () => {
      if (tooBig) {
        return reject(Object.assign(new Error("body too large"), { status: 413 }));
      }
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
        "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
        "access-control-allow-headers": "content-type,authorization",
      });
      return res.end();
    }

    if (url.pathname === "/api/health") {
      return json(res, 200, {
        ok: true,
        service: "chiplab",
        version: "0.3.0",
        wasm: { version: core.version(), bytes: core.wasmBytes },
        chips: CHIPS,
        host,
        upstream: "local",
        cloud: { tokenRequired: Boolean(TOKEN), persistence: "local-json" },
      });
    }
    if (url.pathname === "/api/cloud/info") {
      return json(res, 200, cloudInfo());
    }
    if (url.pathname === "/api/store" && req.method === "GET") {
      if (!authorized(req)) return json(res, 401, { ok: false, error: "unauthorized" });
      return json(res, 200, { ok: true, namespaces: store.list() });
    }
    if (url.pathname.startsWith("/api/store/")) {
      if (!authorized(req)) return json(res, 401, { ok: false, error: "unauthorized" });
      const ns = decodeURIComponent(url.pathname.slice("/api/store/".length));
      if (!/^[a-zA-Z0-9_-]{1,32}$/.test(ns)) return json(res, 400, { ok: false, error: "invalid namespace" });
      if (req.method === "GET") {
        const rec = store.get(ns);
        if (!rec) return json(res, 404, { ok: false, error: "not found", namespace: ns });
        return json(res, 200, { ok: true, namespace: ns, ...rec });
      }
      if (req.method === "PUT" || req.method === "POST") {
        try {
          const body = await readBody(req, MAX_BYTES);
          const meta = store.put(ns, body.data ?? body, body.expectedRevision ?? null);
          return json(res, 200, { ok: true, namespace: ns, ...meta });
        } catch (e) {
          return json(res, e.status || 500, { ok: false, error: String(e.message || e) });
        }
      }
      if (req.method === "DELETE") {
        store.del(ns);
        return json(res, 200, { ok: true, namespace: ns, deleted: true });
      }
      return json(res, 405, { ok: false, error: "GET/PUT/DELETE only" });
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
  console.log(`ChipLab local cloud listening on http://${HOST}:${PORT}`);
  console.log(`  wasm: ${core.wasmBytes} bytes, version 0x${core.version().toString(16)}`);
  console.log(`  chips: ${CHIPS.length}, host: ${host.cpu} / ${host.cores} cores / ${host.memoryGb} GB`);
  console.log(`  data: ${DATA_DIR}`);
  console.log(`  token: ${TOKEN ? "required" : "loopback-only writes"}`);
  for (const u of lanUrls()) console.log(`  LAN: ${u}`);
});
