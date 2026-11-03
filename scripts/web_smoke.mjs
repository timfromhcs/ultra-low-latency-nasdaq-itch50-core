// =============================================================================
// File: scripts/web_smoke.mjs
// Description: Start the local backend, verify the app shell, WASM magic and API,
//              then stop it. This is the CI-safe web gate (Playwright adds the
//              visual/console gate in a browser session).
// =============================================================================
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = 4193;
const child = spawn(process.execPath, ["backend/server.mjs"], {
  cwd: root,
  env: { ...process.env, PORT: String(port), HOST: "127.0.0.1" },
  stdio: ["ignore", "pipe", "pipe"],
});
let log = "";
child.stdout.on("data", (d) => { log += d; });
child.stderr.on("data", (d) => { log += d; });

async function waitFor(url, tries = 50) {
  for (let i = 0; i < tries; i++) {
    try { const r = await fetch(url); if (r.ok) return r; } catch { /* retry */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`server did not start: ${log}`);
}

try {
  const health = await (await waitFor(`http://127.0.0.1:${port}/api/health`)).json();
  if (!health.ok || health.chips.length !== 8) throw new Error("health failed");
  const html = await (await fetch(`http://127.0.0.1:${port}/`)).text();
  for (const id of ["run", "compare-btn", "gpu-canvas", "tape-body", "compare-body"]) {
    if (!html.includes(`id="${id}"`)) throw new Error(`missing #${id}`);
  }
  const wasm = new Uint8Array(await (await fetch(`http://127.0.0.1:${port}/wasm/chiplab_core.wasm`)).arrayBuffer());
  if (wasm[0] !== 0 || wasm[1] !== 0x61 || wasm[2] !== 0x73 || wasm[3] !== 0x6d) throw new Error("bad wasm magic");
  const run = await (await fetch(`http://127.0.0.1:${port}/api/run`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ chip: 1, count: 1000, seed: 7 }),
  })).json();
  if (!run.ok || run.messages !== 1000 || run.errors !== 0) throw new Error("api run failed");
  console.log(`web smoke: ${html.length} B html, ${wasm.length} B wasm, ${run.messages} messages, ${run.gbps.toFixed(2)} Gbps PASS`);
} finally {
  child.kill();
}
