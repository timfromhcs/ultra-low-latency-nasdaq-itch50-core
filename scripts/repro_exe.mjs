// =============================================================================
// File: scripts/repro_exe.mjs
// Description: Reproducible-build check for the Windows single EXE. Builds it
//   twice with `npm run build:exe` and compares SHA-256. Windows only.
//   Writes reports/repro_exe.json.
// =============================================================================
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";

if (process.platform !== "win32") {
  console.error("[FAIL] the EXE build is Windows-only");
  process.exit(2);
}

const exe = "dist/chiplab.exe";
const hash = () =>
  fs.existsSync(exe) ? crypto.createHash("sha256").update(fs.readFileSync(exe)).digest("hex") : null;

function build() {
  fs.rmSync(exe, { force: true });
  execFileSync(process.execPath, ["scripts/build_exe.mjs"], { stdio: "inherit" });
  const h = hash();
  if (!h) throw new Error("build produced no dist/chiplab.exe");
  return h;
}

const a = build();
const b = build();
const status = a === b ? "PASS" : "FAIL";
const report = {
  generatedAt: new Date().toISOString(),
  node: process.version,
  buildA: a,
  buildB: b,
  bytes: fs.statSync(exe).size,
  status,
};
fs.mkdirSync("reports", { recursive: true });
fs.writeFileSync("reports/repro_exe.json", JSON.stringify(report, null, 2) + "\n");
console.log(`[REPRO] EXE A=${a}`);
console.log(`[REPRO] EXE B=${b}`);
console.log(`[REPRO] ${status}`);
process.exit(status === "PASS" ? 0 : 1);
