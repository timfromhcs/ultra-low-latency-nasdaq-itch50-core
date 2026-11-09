// =============================================================================
// File: mcp/server.mjs
// Description: Minimal MCP (stdio JSON-RPC) server for ChipLab.
//   Tools: chiplab.chips, chiplab.run, chiplab.compare, chiplab.book,
//          chiplab.formal_status, chiplab.health, chiplab.cloud_info,
//          chiplab.history, chiplab.release_status, chiplab.sbom,
//          chiplab.synth_status, chiplab.docs
//   No external dependencies. Logs go to stderr; stdout is protocol-only.
// =============================================================================
import readline from "node:readline";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { loadCore, CHIPS, decodeRecord, hostInfo } from "../backend/wasm.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const core = await loadCore();
const host = hostInfo();

const TOOLS = [
  {
    name: "chiplab.chips",
    description: "List the available chip models and their latency families.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.run",
    description: "Generate a deterministic ITCH stream and run one chip model. Returns summary, sample records and top of book.",
    inputSchema: {
      type: "object",
      properties: {
        chip: { type: "integer", minimum: 0, maximum: 7, default: 1 },
        count: { type: "integer", minimum: 1, maximum: 2000000, default: 100000 },
        seed: { type: "integer", minimum: 0, default: 1337 },
        mode: { type: "integer", enum: [0, 1, 2], default: 0, description: "0 raw ITCH, 1 MoldUDP64, 2 Ethernet+Mold" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "chiplab.compare",
    description: "Run every chip model against the golden parser and return a PASS/FAIL comparison table.",
    inputSchema: {
      type: "object",
      properties: {
        count: { type: "integer", minimum: 1, maximum: 1000000, default: 100000 },
        seed: { type: "integer", minimum: 0, default: 1337 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "chiplab.book",
    description: "Build the top-of-book table for a deterministic stream.",
    inputSchema: {
      type: "object",
      properties: {
        count: { type: "integer", minimum: 1, maximum: 1000000, default: 100000 },
        seed: { type: "integer", minimum: 0, default: 1337 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "chiplab.formal_status",
    description: "Return the last formal verification report committed in reports/formal.json.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.health",
    description: "Return service version, WASM ABI, host summary and which evidence reports exist.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.cloud_info",
    description: "Describe the local cloud data directory and namespaces. Read-only; never starts a server.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.history",
    description: "Summarize the local cloud run history (revision, updatedAt, run count, last summary). No raw payloads.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.release_status",
    description: "Check version consistency, gate scorecard, changelog and required artifacts for a release.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.sbom",
    description: "Summarize reports/sbom.json: component count, scopes and a few notable components.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.synth_status",
    description: "Parse reports/synth_*.log and return the last cell count per width.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "chiplab.docs",
    description: "Return one documentation file from a fixed catalog. Never reads arbitrary paths.",
    inputSchema: {
      type: "object",
      properties: {
        doc: {
          type: "string",
          enum: ["architecture", "benchmarks", "datasheet", "register-map", "integration-guide", "errata", "api", "long-term-plan", "release-plan", "mold-backpressure", "mcp-security", "readme", "changelog"],
          default: "architecture",
        },
      },
      additionalProperties: false,
    },
  },
];

const ALLOWED = {
  "chiplab.chips": [],
  "chiplab.formal_status": [],
  "chiplab.health": [],
  "chiplab.cloud_info": [],
  "chiplab.history": [],
  "chiplab.release_status": [],
  "chiplab.sbom": [],
  "chiplab.synth_status": [],
  "chiplab.docs": ["doc"],
  "chiplab.run": ["chip", "count", "seed", "mode"],
  "chiplab.compare": ["count", "seed"],
  "chiplab.book": ["count", "seed"],
};

const DOCS = {
  "architecture": "docs/architecture.md",
  "benchmarks": "docs/benchmarks.md",
  "datasheet": "docs/datasheet.md",
  "register-map": "docs/register-map.md",
  "integration-guide": "docs/integration-guide.md",
  "errata": "docs/errata.md",
  "api": "docs/api.md",
  "long-term-plan": "LONG_TERM_PLAN.md",
  "release-plan": "STABLE_RELEASE_PLAN.md",
  "mold-backpressure": "docs/design/mold-backpressure.md",
  "mcp-security": "mcp/SECURITY.md",
  "readme": "README.md",
  "changelog": "CHANGELOG.md",
};

function validateArgs(name, args) {
  if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("arguments must be an object");
  const allowed = ALLOWED[name];
  if (!allowed) throw new Error(`unknown tool: ${name}`);
  for (const k of Object.keys(args)) if (!allowed.includes(k)) throw new Error(`unexpected argument: ${k}`);
  const out = {};
  if (allowed.includes("doc")) {
    const d = args.doc ?? "architecture";
    if (typeof d !== "string" || !(d in DOCS)) throw new Error(`doc must be one of: ${Object.keys(DOCS).join(", ")}`);
    out.doc = d;
  }
  if (allowed.includes("count")) {
    const n = Number(args.count ?? 100000);
    if (!Number.isInteger(n) || n < 1 || n > 2_000_000) throw new Error("count must be an integer in 1..2000000");
    out.count = n;
  }
  if (allowed.includes("seed")) {
    const n = Number(args.seed ?? 1337);
    if (!Number.isInteger(n) || n < 0 || n > 2 ** 31 - 1) throw new Error("seed must be an integer in 0..2^31-1");
    out.seed = n;
  }
  if (allowed.includes("chip")) {
    const n = Number(args.chip ?? 1);
    if (!Number.isInteger(n) || n < 0 || n > 7) throw new Error("chip must be an integer in 0..7");
    out.chip = n;
  }
  if (allowed.includes("mode")) {
    const n = Number(args.mode ?? 0);
    if (![0, 1, 2].includes(n)) throw new Error("mode must be 0, 1 or 2");
    out.mode = n;
  }
  return out;
}

function audit(name, args, result, error) {
  try {
    const h = crypto.createHash("sha256").update(JSON.stringify(args)).digest("hex").slice(0, 16);
    const line = JSON.stringify({
      ts: new Date().toISOString(), tool: name, argsHash: h,
      ok: !error, result: error ? "error" : (result?.rows ? `${result.rows.length} rows` : result?.messages ? `${result.messages} msgs` : "ok"),
    });
    fs.mkdirSync(path.resolve(root, "reports"), { recursive: true });
    fs.appendFileSync(path.resolve(root, "reports/mcp-audit.log"), line + "\n");
  } catch { /* audit must never break a tool */ }
}

function summary(header, streamBytes) {
  const cycles = Math.max(1, header.cycles);
  const ns = cycles * 3.1;
  return {
    chip: header.chip, messages: header.count, cycles, ns,
    gbps: (header.bytesIn * 8) / (ns * 1e-9) / 1e9,
    mps: header.count / (ns * 1e-9) / 1e6,
    bytesIn: header.bytesIn, streamBytes, corrupt: header.corrupt, frames: header.frames,
  };
}

function readJson(rel, fallback = null) {
  try { return JSON.parse(fs.readFileSync(path.resolve(root, rel), "utf8")); } catch { return fallback; }
}

function dataDir() {
  return path.resolve(root, process.env.CHIPLAB_DATA_DIR || ".data");
}

function listNamespaces() {
  try {
    return fs.readdirSync(dataDir())
      .filter((f) => f.endsWith(".json"))
      .map((f) => f.slice(0, -5))
      .filter((n) => /^[a-zA-Z0-9_-]{1,32}$/.test(n))
      .slice(0, 64);
  } catch { return []; }
}

function runTool(name, args = {}) {
  if (name === "chiplab.chips") return { chips: CHIPS, host };
  if (name === "chiplab.health") {
    const reports = ["formal.json", "scorecard.json", "sbom.json", "sim_1m.txt", "mutation.json"]
      .map((f) => ({ file: f, present: fs.existsSync(path.resolve(root, "reports", f)) }));
    return {
      ok: true,
      service: "chiplab-mcp",
      version: readJson("package.json", {})?.version || "unknown",
      wasm: { version: core.version(), bytes: core.wasmBytes },
      chips: CHIPS.length,
      host,
      reports,
    };
  }
  if (name === "chiplab.cloud_info") {
    return {
      ok: true,
      service: "chiplab-local-cloud",
      version: readJson("package.json", {})?.version || "unknown",
      dataDir: path.basename(dataDir()),
      namespaces: listNamespaces(),
      persistence: "local-json",
      note: "Read-only view. Start backend/server.mjs or chiplab.exe for the HTTP service.",
    };
  }
  if (name === "chiplab.history") {
    const rec = readJson(path.join(path.basename(dataDir()), "default.json"));
    if (!rec) return { ok: true, exists: false, runs: 0, note: "no local cloud history" };
    const runs = Array.isArray(rec.data?.runs) ? rec.data.runs : [];
    return {
      ok: true,
      exists: true,
      revision: rec.revision ?? null,
      updatedAt: rec.updatedAt ?? null,
      runs: runs.length,
      lastRun: rec.data?.lastRun ?? null,
    };
  }
  if (name === "chiplab.release_status") {
    const expected = readJson("package.json", {})?.version;
    const versions = {};
    for (const [k, rel] of Object.entries({
      npm: "packages/npm/package.json",
      native: "native/Cargo.toml",
      wasm: "wasm-core/Cargo.toml",
      python: "packages/python/pyproject.toml",
    })) {
      const text = fs.readFileSync(path.resolve(root, rel), "utf8");
      versions[k] = /"version"\s*:\s*"([^"]+)"/.exec(text)?.[1] || /^version\s*=\s*"([^"]+)"/m.exec(text)?.[1] || "?";
    }
    const changelog = fs.existsSync(path.resolve(root, "CHANGELOG.md"))
      ? fs.readFileSync(path.resolve(root, "CHANGELOG.md"), "utf8") : "";
    const scorecard = readJson("reports/scorecard.json", null);
    const artifacts = ["web/wasm/chiplab_core.wasm", "reports/sbom.json"]
      .map((rel) => ({ path: rel, present: fs.existsSync(path.resolve(root, rel)) }));
    return {
      version: expected,
      versions,
      consistent: Object.values(versions).every((v) => v === expected),
      changelogHasVersion: Boolean(expected && changelog.includes(`## ${expected}`)),
      scorecard: scorecard ? { score: scorecard.score, deep: scorecard.deep, generatedAt: scorecard.generatedAt } : null,
      artifacts,
    };
  }
  if (name === "chiplab.sbom") {
    const sbom = readJson("reports/sbom.json", null);
    if (!sbom) return { ok: false, note: "run node scripts/sbom.mjs" };
    const components = Array.isArray(sbom.components) ? sbom.components : [];
    const scopes = {};
    for (const c of components) scopes[c.scope || "runtime"] = (scopes[c.scope || "runtime"] || 0) + 1;
    return {
      ok: true,
      bomFormat: sbom.bomFormat,
      specVersion: sbom.specVersion,
      component: sbom.metadata?.component || null,
      count: components.length,
      scopes,
      sample: components.slice(0, 12).map((c) => ({ name: c.name, version: c.version, scope: c.scope })),
    };
  }
  if (name === "chiplab.synth_status") {
    const dir = path.resolve(root, "reports");
    const out = {};
    try {
      for (const f of fs.readdirSync(dir).filter((x) => /^synth_\d+\.log$/.test(x))) {
        const text = fs.readFileSync(path.join(dir, f), "utf8");
        const cells = [...text.matchAll(/Number of cells:\s+(\d+)/g)].map((m) => Number(m[1]));
        const dff = [...text.matchAll(/Number of \$_(S?DFF[^\s]*)/g)].length;
        out[f.replace(/^synth_|\.log$/g, "")] = { lastCells: cells.at(-1) ?? null, cellLines: cells.length, dffCells: dff };
      }
    } catch { /* no reports */ }
    return { ok: Object.keys(out).length > 0, widths: out };
  }
  if (name === "chiplab.docs") {
    const rel = DOCS[args.doc || "architecture"];
    const text = fs.readFileSync(path.resolve(root, rel), "utf8");
    return { doc: args.doc || "architecture", path: rel, bytes: Buffer.byteLength(text), truncated: text.length > 20000, text: text.slice(0, 20000) };
  }
  if (name === "chiplab.formal_status") {
    const p = path.resolve(root, "reports/formal.json");
    return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : { status: "unknown", note: "run formal/run_formal.sh" };
  }
  const count = Math.max(1, Math.min(2_000_000, Number(args.count) || 100000));
  const seed = Math.max(0, Number(args.seed) || 1337);
  const stream = core.generate(count, Number(args.mode) || 0, seed);
  if (name === "chiplab.compare") {
    return { seed, streamBytes: stream.len, rows: core.compare(stream) };
  }
  if (name === "chiplab.book") {
    return { seed, streamBytes: stream.len, book: core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 64) };
  }
  if (name === "chiplab.run") {
    const chip = Math.max(0, Math.min(7, Number(args.chip ?? 1)));
    const r = core.run(chip, stream);
    const records = [];
    for (let i = 0, off = 0; i < 24 && off + 80 <= r.records.length; i++, off += 80) records.push(decodeRecord(r.records, off));
    return {
      ...summary(r.header, stream.len),
      seed, mode: Number(args.mode) || 0,
      book: core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 16),
      records,
    };
  }
  throw new Error(`unknown tool: ${name}`);
}

function send(obj) {
  process.stdout.write(JSON.stringify(obj, (_k, v) => (typeof v === "bigint" ? v.toString() : v)) + "\n");
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  const { id, method, params } = msg;
  try {
    if (method === "initialize") {
      send({ jsonrpc: "2.0", id, result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "chiplab", version: "0.3.1" },
      }});
      return;
    }
    if (method === "notifications/initialized" || method?.startsWith("notifications/")) return;
    if (method === "ping") { send({ jsonrpc: "2.0", id, result: {} }); return; }
    if (method === "tools/list") { send({ jsonrpc: "2.0", id, result: { tools: TOOLS } }); return; }
    if (method === "tools/call") {
      const name = params?.name;
      let result, err;
      try {
        const args = validateArgs(name, params?.arguments || {});
        result = runTool(name, args);
      } catch (e) {
        err = e;
        throw e;
      } finally {
        audit(name, params?.arguments || {}, result, err);
      }
      send({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] } });
      return;
    }
    send({ jsonrpc: "2.0", id, error: { code: -32601, message: `method not found: ${method}` } });
  } catch (err) {
    send({ jsonrpc: "2.0", id, error: { code: -32000, message: String(err?.message || err) } });
  }
});

process.stderr.write(`ChipLab MCP ready · ${CHIPS.length} chips · ${host.cpu}\n`);
