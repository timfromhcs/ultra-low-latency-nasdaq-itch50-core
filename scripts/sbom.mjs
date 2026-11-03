// =============================================================================
// File: scripts/sbom.mjs
// Description: Generate a small CycloneDX-style SBOM from the lockfiles plus the
//              shipped WASM hash. No network, no dependency on external tools.
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const components = [];

function add(type, name, version, extra = {}) {
  components.push({ type, name, version, ...extra });
}

// npm / Node build tooling
try {
  const lock = JSON.parse(fs.readFileSync(path.join(root, "package-lock.json"), "utf8"));
  for (const [p, v] of Object.entries(lock.packages || {})) {
    if (!p || p === "") continue;
    add("library", p.replace(/^node_modules\//, ""), v.version || "unknown", { scope: "build" });
  }
} catch { /* optional */ }

// Rust workspace lockfiles
for (const rel of ["wasm-core/Cargo.lock", "native/Cargo.lock"]) {
  try {
    const text = fs.readFileSync(path.join(root, rel), "utf8");
    const blocks = text.split("[[package]]").slice(1);
    for (const b of blocks) {
      const name = /name = "([^"]+)"/.exec(b)?.[1];
      const version = /version = "([^"]+)"/.exec(b)?.[1];
      if (name && version) add("library", name, version, { scope: rel.startsWith("native") ? "native" : "wasm" });
    }
  } catch { /* optional */ }
}

// Python package declared in pyproject (no third-party runtime deps)
try {
  const py = fs.readFileSync(path.join(root, "packages/python/pyproject.toml"), "utf8");
  const name = /name = "([^"]+)"/.exec(py)?.[1];
  const version = /version = "([^"]+)"/.exec(py)?.[1];
  if (name && version) add("library", name, version, { scope: "python" });
} catch { /* optional */ }

// Shipped WASM artifact
try {
  const wasm = fs.readFileSync(path.join(root, "web/wasm/chiplab_core.wasm"));
  add("file", "chiplab_core.wasm", "0.2.0", {
    hashes: [{ alg: "SHA-256", content: crypto.createHash("sha256").update(wasm).digest("hex") }],
    scope: "runtime",
  });
} catch { /* optional */ }

const unique = [...new Map(components.map((c) => [`${c.name}@${c.version}`, c])).values()];
const bom = {
  bomFormat: "CycloneDX",
  specVersion: "1.5",
  version: 1,
  metadata: { timestamp: new Date().toISOString(), component: { type: "application", name: "chiplab", version: "0.3.0" } },
  components: unique,
};
fs.mkdirSync(path.join(root, "reports"), { recursive: true });
fs.writeFileSync(path.join(root, "reports/sbom.json"), JSON.stringify(bom, null, 2));
console.log(`SBOM: ${unique.length} components → reports/sbom.json`);
