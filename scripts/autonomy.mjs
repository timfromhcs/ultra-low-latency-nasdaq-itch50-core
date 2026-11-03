#!/usr/bin/env node
// =============================================================================
// File: scripts/autonomy.mjs
// Description: Queue-based, bounded autonomy tick. Runs the next pending gate,
//              records the result, and never pretends a failed gate passed.
//   node scripts/autonomy.mjs           # next pending task
//   node scripts/autonomy.mjs --all     # every pending task
//   node scripts/autonomy.mjs --list    # status only
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const queuePath = path.join(root, "autonomy/queue.json");
const logPath = path.join(root, "reports/autonomy.log");
fs.mkdirSync(path.dirname(logPath), { recursive: true });

const q = JSON.parse(fs.readFileSync(queuePath, "utf8"));
const args = process.argv.slice(2);
if (args.includes("--list")) {
  for (const t of q.tasks) console.log(`${t.status.padEnd(8)} ${t.id.padEnd(20)} ${t.cmd}`);
  process.exit(0);
}

const all = args.includes("--all");
let ran = 0, failed = 0;
for (const task of q.tasks) {
  if (task.status === "done") continue;
  const t0 = new Date();
  console.log(`[tick] ${task.id}`);
  const r = spawnSync(task.cmd, {
    cwd: root, shell: true, encoding: "utf8", timeout: 15 * 60 * 1000,
  });
  const ok = r.status === 0;
  const line = `[${t0.toISOString()}] ${ok ? "PASS" : "FAIL"} ${task.id} :: ${task.cmd}\n`;
  fs.appendFileSync(logPath, line + (ok ? "" : (r.stdout || "") + (r.stderr || "") + "\n"));
  task.status = ok ? "done" : "failed";
  task.lastRun = t0.toISOString();
  task.lastResult = ok ? "PASS" : "FAIL";
  ran++;
  if (!ok) failed++;
  if (!all) break;
}
fs.writeFileSync(queuePath, JSON.stringify(q, null, 2) + "\n");
console.log(`[tick] ran ${ran}, failed ${failed}`);
process.exit(failed ? 1 : 0);
