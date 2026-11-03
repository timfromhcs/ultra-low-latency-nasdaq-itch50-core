// =============================================================================
// File: mcp/client_smoke.mjs
// Description: Minimal MCP client smoke test for mcp/server.mjs.
// Run: node mcp/client_smoke.mjs
// =============================================================================
import { spawn } from "node:child_process";
import readline from "node:readline";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const child = spawn(process.execPath, [path.resolve(here, "server.mjs")], {
  cwd: path.resolve(here, ".."),
  stdio: ["pipe", "pipe", "inherit"],
});
const rl = readline.createInterface({ input: child.stdout });
const pending = new Map();
let seq = 1;

rl.on("line", (line) => {
  const msg = JSON.parse(line);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  }
});

function call(method, params) {
  const id = seq++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout: ${method}`)), 30000);
    pending.set(id, (m) => { clearTimeout(t); m.error ? reject(new Error(m.error.message)) : resolve(m.result); });
  });
}

try {
  const init = await call("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
  console.log("initialize:", init.serverInfo);
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const tools = await call("tools/list", {});
  console.log("tools:", tools.tools.map((t) => t.name).join(", "));
  const chips = await call("tools/call", { name: "chiplab.chips", arguments: {} });
  const chipData = JSON.parse(chips.content[0].text);
  console.log("chips:", chipData.chips.length);
  const cmp = await call("tools/call", { name: "chiplab.compare", arguments: { count: 5000, seed: 7 } });
  const rows = JSON.parse(cmp.content[0].text).rows;
  console.log("compare:", rows.map((r) => `${r.key}:${r.status}`).join(" "));
  const run = await call("tools/call", { name: "chiplab.run", arguments: { chip: 1, count: 5000, seed: 7 } });
  const out = JSON.parse(run.content[0].text);
  console.log("run:", out.messages, out.gbps.toFixed(2), "Gbps", out.records.length, "sample records");
  if (rows.find((r) => r.key === "lossy").status !== "FAIL") throw new Error("lossy must fail");
  if (out.messages !== 5000) throw new Error("run count mismatch");
  console.log("MCP SMOKE PASS");
} finally {
  child.stdin.end();
  child.kill();
}
