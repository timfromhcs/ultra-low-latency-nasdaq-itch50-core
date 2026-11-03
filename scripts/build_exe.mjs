// =============================================================================
// File: scripts/build_exe.mjs
// Description: Build a single-file Windows executable with Node SEA.
//   1. inline web assets as base64
//   2. bundle scripts/sea_entry.mjs with esbuild
//   3. create the SEA blob and inject it into a copy of node.exe
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const web = path.resolve(root, "web");
const dist = path.resolve(root, "dist");

function walk(dir, base = dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p, base));
    else out.push(path.relative(base, p).replaceAll("\\", "/"));
  }
  return out;
}

fs.mkdirSync(dist, { recursive: true });
const assets = {};
for (const rel of walk(web)) {
  if (rel.endsWith(".map")) continue;
  assets[rel] = fs.readFileSync(path.join(web, rel)).toString("base64");
}
const generated = path.join(dist, "web_assets.generated.mjs");
fs.writeFileSync(generated, `export const ASSETS = ${JSON.stringify(assets, null, 0)};\n`);
console.log(`[exe] embedded ${Object.keys(assets).length} web files (${(fs.statSync(generated).size / 1024).toFixed(0)} KB asset module)`);

const bundle = path.join(dist, "chiplab-sea.cjs");
await build({
  entryPoints: [path.resolve(here, "sea_entry.mjs")],
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node22",
  outfile: bundle,
  logLevel: "warning",
});
console.log(`[exe] bundled ${(fs.statSync(bundle).size / 1024).toFixed(0)} KB`);

const seaConfig = path.join(dist, "sea-config.json");
fs.writeFileSync(seaConfig, JSON.stringify({
  main: bundle,
  output: path.join(dist, "sea-prep.blob"),
  disableExperimentalSEAWarning: true,
  useSnapshot: false,
  useCodeCache: false,
}, null, 2));

console.log("[exe] generating SEA blob");
execFileSync(process.execPath, ["--experimental-sea-config", seaConfig], { stdio: "inherit" });

const exe = path.join(dist, "chiplab.exe");
fs.copyFileSync(process.execPath, exe);

// Remove the Authenticode signature before injecting (best-effort; the host
// may not have signtool).
try {
  execFileSync("signtool", ["remove", "/s", exe], { stdio: "ignore" });
} catch { /* not installed or unsigned */ }

const postject = path.resolve(root, "node_modules/postject/dist/cli.js");
console.log("[exe] injecting NODE_SEA_BLOB");
execFileSync(process.execPath, [
  postject, exe, "NODE_SEA_BLOB", path.join(dist, "sea-prep.blob"),
  "--sentinel-fuse", "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2",
  "--overwrite",
], { stdio: "inherit" });

console.log(`[exe] built ${exe} (${(fs.statSync(exe).size / 1024 / 1024).toFixed(1)} MB)`);
