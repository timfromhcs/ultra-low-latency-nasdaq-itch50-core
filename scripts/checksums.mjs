#!/usr/bin/env node
// =============================================================================
// File: scripts/checksums.mjs
// Description: Write a SHA-256 manifest for release artifacts.
//   node scripts/checksums.mjs [dir] [outFile]
//   default dir: dist/release, default out: dist/release/SHA256SUMS.txt
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const dir = path.resolve(process.argv[2] || "dist/release");
const out = process.argv[3] ? path.resolve(process.argv[3]) : path.join(dir, "SHA256SUMS.txt");

if (!fs.existsSync(dir)) {
  console.error(`checksums: directory not found: ${dir}`);
  process.exit(2);
}

const files = fs.readdirSync(dir, { withFileTypes: true })
  .filter((e) => e.isFile() && e.name !== path.basename(out))
  .map((e) => e.name)
  .sort();

if (!files.length) {
  console.error(`checksums: no artifacts in ${dir}`);
  process.exit(1);
}

const lines = files.map((name) => {
  const hash = crypto.createHash("sha256").update(fs.readFileSync(path.join(dir, name))).digest("hex");
  return `${hash}  ${name}`;
});

fs.writeFileSync(out, lines.join("\n") + "\n");
console.log(`checksums: ${lines.length} artifacts -> ${path.relative(process.cwd(), out)}`);
for (const line of lines) console.log(`  ${line}`);
