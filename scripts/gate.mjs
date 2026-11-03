#!/usr/bin/env node
// =============================================================================
// File: scripts/gate.mjs
// Description: One-command gate. Runs the portable checks and writes a scorecard.
//   node scripts/gate.mjs          # fast (CI-friendly)
//   node scripts/gate.mjs --deep   # + 1M RTL + formal matrix (WSL)
// =============================================================================
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const deep = process.argv.includes("--deep");
fs.mkdirSync(path.join(root, "reports"), { recursive: true });

const PY = process.platform === "win32" ? "python" : "python3";
const checks = [
  ["model-tests", `${PY} -m pytest -q tb/test_model.py`],
  ["wasm-smoke", "node scripts/wasm_smoke.mjs"],
  ["wasm-crosscheck", `${PY} scripts/check_wasm_fixture.py`],
  ["backend-compare", "node backend/run.mjs --compare --count 20000"],
  ["mcp", "node mcp/client_smoke.mjs"],
  ["web-smoke", "node scripts/web_smoke.mjs"],
  ["sbom", "node scripts/sbom.mjs"],
  ["vercel-api", "node scripts/build_vercel.mjs && node scripts/test_vercel_api.mjs"],
];
if (deep) {
  checks.push(["formal-z3", "wsl -d Ubuntu /mnt/e/chips/main/formal/run_formal.sh z3"]);
  checks.push(["native-bins", "node scripts/check_native_bins.mjs"]);
}

const rows = [];
let failed = 0;
for (const [name, cmd] of checks) {
  const t0 = Date.now();
  const r = spawnSync(cmd, { cwd: root, shell: true, encoding: "utf8", timeout: 20 * 60 * 1000 });
  const ok = r.status === 0;
  if (!ok) failed++;
  const row = { name, cmd, status: ok ? "PASS" : "FAIL", ms: Date.now() - t0, tail: (r.stdout || "").trim().slice(-800) };
  rows.push(row);
  console.log(`${ok ? "PASS" : "FAIL"} ${name} (${row.ms} ms)`);
  if (!ok) console.log((r.stdout || "") + (r.stderr || ""));
}
const score = Math.round((rows.filter((r) => r.status === "PASS").length / rows.length) * 100);
const report = { generatedAt: new Date().toISOString(), deep, score, rows };
fs.writeFileSync(path.join(root, "reports/scorecard.json"), JSON.stringify(report, null, 2));
console.log(`\nscorecard: ${score}% (${rows.length - failed}/${rows.length}) → reports/scorecard.json`);
process.exit(failed ? 1 : 0);
