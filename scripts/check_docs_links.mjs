// =============================================================================
// File: scripts/check_docs_links.mjs
// Description: Check relative Markdown links in the repository docs. Skips
//   http(s)/mailto links, pure anchors and fenced code blocks. Writes
//   reports/links.json and exits non-zero on a missing target.
// =============================================================================
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const files = [];

function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name.startsWith(".git")) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith(".md")) files.push(p);
  }
}

for (const f of ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LONG_TERM_PLAN.md", "STABLE_RELEASE_PLAN.md"]) {
  if (fs.existsSync(f)) files.push(path.join(root, f));
}
for (const d of ["docs", "openlane", "mcp", "caravel", ".opencode"]) {
  if (fs.existsSync(d)) walk(path.join(root, d));
}

const linkRe = /\[[^\]]*\]\(([^)\s]+)\)/g;
const artifactRe = /(?<![\w/.-])reports\/[A-Za-z0-9_.-]+\.json\b/g;
const rows = [];
let missing = 0;
let artifacts = 0;

for (const file of files) {
  const rel = path.relative(root, file).replace(/\\/g, "/");
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  let fence = false;
  lines.forEach((line, i) => {
    if (/^\s*```/.test(line)) { fence = !fence; return; }
    if (fence) return;
    for (const m of line.matchAll(artifactRe)) {
      artifacts++;
      if (!fs.existsSync(path.join(root, m[0]))) {
        missing++;
        rows.push({ file: rel, line: i + 1, target: m[0], kind: "artifact" });
      }
    }
    for (const m of line.matchAll(linkRe)) {
      let target = m[1];
      if (/^(https?:|mailto:|#)/.test(target)) continue;
      target = target.split("#")[0];
      if (!target) continue;
      const resolved = target.startsWith("/")
        ? path.join(root, target.slice(1))
        : path.resolve(path.dirname(file), decodeURIComponent(target));
      const ok = fs.existsSync(resolved);
      if (!ok) {
        missing++;
        rows.push({ file: rel, line: i + 1, target, resolved: path.relative(root, resolved).replace(/\\/g, "/"), kind: "link" });
      }
    }
  });
}

fs.mkdirSync("reports", { recursive: true });
fs.writeFileSync("reports/links.json", JSON.stringify({ files: files.length, artifacts, missing, rows }, null, 2) + "\n");

if (missing) {
  console.error(`[FAIL] ${missing} dead reference(s):`);
  for (const r of rows) console.error(`  ${r.file}:${r.line} -> ${r.target}`);
  process.exit(1);
}
console.log(`[OK] ${files.length} Markdown files, ${artifacts} report references, no dead links`);
