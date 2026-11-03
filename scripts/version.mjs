#!/usr/bin/env node
// =============================================================================
// File: scripts/version.mjs
// Description: Single source of truth for the ChipLab release version.
//   node scripts/version.mjs              # print detected versions
//   node scripts/version.mjs --set 0.3.0  # update package/cargo/pyproject/wasm
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const setIndex = args.indexOf("--set");
const newVersion = setIndex >= 0 ? args[setIndex + 1] : null;
if (newVersion && !/^\d+\.\d+\.\d+$/.test(newVersion)) {
  console.error("version must be semver X.Y.Z");
  process.exit(2);
}

function read(rel) { return fs.readFileSync(path.join(root, rel), "utf8"); }
function write(rel, text) { fs.writeFileSync(path.join(root, rel), text); }
function replaceOnce(rel, re, value) {
  const text = read(rel);
  if (!re.test(text)) throw new Error(`pattern not found in ${rel}`);
  write(rel, text.replace(re, value));
}

const files = {
  root: "package.json",
  npm: "packages/npm/package.json",
  native: "native/Cargo.toml",
  wasm: "wasm-core/Cargo.toml",
  python: "packages/python/pyproject.toml",
};
const current = JSON.parse(read(files.root)).version;

if (!newVersion) {
  const rows = Object.entries(files).map(([k, rel]) => {
    const t = read(rel);
    const m = /"version"\s*:\s*"([^"]+)"/.exec(t) || /^version\s*=\s*"([^"]+)"/m.exec(t);
    return [k, m ? m[1] : "?"];
  });
  const wasmVersion = /version\(\)\s*->\s*u32\s*\{\s*0x([0-9A-Fa-f_]+)\s*\}/.exec(read("wasm-core/src/lib.rs"))?.[1];
  rows.push(["wasm-version", wasmVersion || "?"]);
  console.log(rows.map(([k, v]) => `${k.padEnd(12)} ${v}`).join("\n"));
  process.exit(0);
}

// package.json files (preserve formatting)
for (const rel of [files.root, files.npm]) {
  replaceOnce(rel, /("version"\s*:\s*")[^"]+(")/, `$1${newVersion}$2`);
}
// Cargo.toml package version (first version occurrence)
for (const rel of [files.native, files.wasm]) {
  replaceOnce(rel, /(^version\s*=\s*")[^"]+(")/m, `$1${newVersion}$2`);
}
// pyproject
replaceOnce(files.python, /(^version\s*=\s*")[^"]+(")/m, `$1${newVersion}$2`);

// WASM ABI version: 0x00030000 for 0.3.0
const [maj, min, patch] = newVersion.split(".").map(Number);
const hex = `0x${maj.toString(16).padStart(2, "0")}${min.toString(16).padStart(2, "0")}${patch.toString(16).padStart(2, "0")}`;
replaceOnce("wasm-core/src/lib.rs", /(pub extern "C" fn version\(\) -> u32 \{ )0x[0-9A-Fa-f_]+( \})/, `$1${hex}$2`);

// MCP serverInfo
replaceOnce("mcp/server.mjs", /(serverInfo:\s*\{\s*name:\s*"chiplab",\s*version:\s*")[^"]+(")/, `$1${newVersion}$2`);
// SBOM metadata
replaceOnce("scripts/sbom.mjs", /(name:\s*"chiplab",\s*version:\s*")[^"]+(")/, `$1${newVersion}$2`);

console.log(`set version ${current} -> ${newVersion}`);
console.log("Next: cargo build wasm, copy web/wasm/chiplab_core.wasm, update CHANGELOG/README.");
