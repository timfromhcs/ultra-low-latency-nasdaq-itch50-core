// =============================================================================
// File: mcp/server.mjs
// Description: Minimal MCP (stdio JSON-RPC) server for ChipLab.
//   Tools: chiplab.chips, chiplab.run, chiplab.compare, chiplab.book,
//          chiplab.formal_status
//   No external dependencies. Logs go to stderr; stdout is protocol-only.
// =============================================================================
import readline from "node:readline";
import fs from "node:fs";
import path from "node:path";
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
];

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

function runTool(name, args = {}) {
  if (name === "chiplab.chips") return { chips: CHIPS, host };
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
        serverInfo: { name: "chiplab", version: "0.2.0" },
      }});
      return;
    }
    if (method === "notifications/initialized" || method?.startsWith("notifications/")) return;
    if (method === "ping") { send({ jsonrpc: "2.0", id, result: {} }); return; }
    if (method === "tools/list") { send({ jsonrpc: "2.0", id, result: { tools: TOOLS } }); return; }
    if (method === "tools/call") {
      const name = params?.name;
      const args = params?.arguments || {};
      const result = runTool(name, args);
      send({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] } });
      return;
    }
    send({ jsonrpc: "2.0", id, error: { code: -32601, message: `method not found: ${method}` } });
  } catch (err) {
    send({ jsonrpc: "2.0", id, error: { code: -32000, message: String(err?.message || err) } });
  }
});

process.stderr.write(`ChipLab MCP ready · ${CHIPS.length} chips · ${host.cpu}\n`);
