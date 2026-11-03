#!/usr/bin/env node
// =============================================================================
// File: scripts/release_check.mjs
// Description: Pre-release consistency and artifact check. Exits non-zero when a
//              version, checksum, or required artifact is missing.
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (rel) => fs.readFileSync(path.join(root, rel), "utf8");
const version = JSON.parse(read("package.json")).version;
const expected = version;

const checks = [];
function check(name, ok, detail = "") {
  checks.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? " — " + detail : ""}`);
}

for (const rel of ["packages/npm/package.json", "native/Cargo.toml", "wasm-core/Cargo.toml", "packages/python/pyproject.toml"]) {
  const t = read(rel);
  const m = /"version"\s*:\s*"([^"]+)"/.exec(t) || /^version\s*=\s*"([^"]+)"/m.exec(t);
  check(`version ${rel}`, m?.[1] === expected, `${m?.[1]} vs ${expected}`);
}
const wasmHex = /version\(\)\s*->\s*u32\s*\{\s*0x([0-9A-Fa-f_]+)\s*\}/.exec(read("wasm-core/src/lib.rs"))?.[1];
const [maj, min, patch] = expected.split(".").map(Number);
const expectedHex = `${maj.toString(16).padStart(2, "0")}${min.toString(16).padStart(2, "0")}${patch.toString(16).padStart(2, "0")}`;
check("wasm ABI version", wasmHex?.toLowerCase() === expectedHex.toLowerCase(), `${wasmHex} vs ${expectedHex}`);

const changelog = read("CHANGELOG.md");
check("changelog has version", changelog.includes(`## ${expected}`), `## ${expected}`);
const readme = read("README.md");
check("README mentions version", readme.includes(expected), version);
const vercelHealth = /version:\s*"([^"]+)"/.exec(read("api/_core.mjs"))?.[1];
check("vercel health version", vercelHealth === expected, vercelHealth);

for (const rel of ["web/wasm/chiplab_core.wasm", "reports/sbom.json"]) {
  check(`artifact ${rel}`, fs.existsSync(path.join(root, rel)));
}
if (fs.existsSync(path.join(root, "reports/sbom.json"))) {
  const sbom = JSON.parse(read("reports/sbom.json"));
  check("sbom metadata version", sbom.metadata?.component?.version === expected, sbom.metadata?.component?.version);
}

// Artifact hashes when present
const artifacts = [
  "dist/chiplab.exe",
  `packages/npm/chiplab-core-${expected}.tgz`,
  `packages/python/dist/chiplab_itch-${expected}-py3-none-any.whl`,
  `packages/python/dist/chiplab_itch-${expected}.tar.gz`,
];
for (const rel of artifacts) {
  const p = path.join(root, rel);
  if (fs.existsSync(p)) {
    const h = crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
    console.log(`HASH ${rel} ${h}`);
  }
}

const failed = checks.filter((c) => !c.ok);
console.log(`release_check: ${checks.length - failed.length}/${checks.length} PASS`);
process.exit(failed.length ? 1 : 0);
