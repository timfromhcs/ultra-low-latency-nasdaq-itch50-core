// =============================================================================
// File: scripts/check_reports.mjs
// Description: Validate the immutable evidence artifacts under reports/.
//   Every reports/openlane_*.json must parse, carry a tag that matches its file
//   name, a generatedAt timestamp, and a non-trivial metrics object. Reports whose
//   name ends in "-full" must also contain post-route timing/DRC/LVS summaries.
// Run: node scripts/check_reports.mjs
// =============================================================================
import fs from "node:fs";
import path from "node:path";

const dir = "reports";
const files = fs
  .readdirSync(dir)
  .filter((f) => f.startsWith("openlane_") && f.endsWith(".json"))
  .sort();

if (files.length === 0) {
  console.error("[FAIL] no openlane report artifacts found");
  process.exit(2);
}

let failed = 0;
const fail = (file, msg) => {
  failed++;
  console.error(`[FAIL] ${file}: ${msg}`);
};

for (const file of files) {
  const full = path.join(dir, file);
  let report;
  try {
    report = JSON.parse(fs.readFileSync(full, "utf8"));
  } catch (e) {
    fail(file, `invalid JSON (${e.message})`);
    continue;
  }
  const tag = String(report.tag ?? "");
  if (!tag) fail(file, "missing tag");
  if (tag && !file.startsWith(`openlane_${tag}`)) {
    fail(file, `tag '${tag}' does not match the file name`);
  }
  if (!report.generatedAt || Number.isNaN(Date.parse(report.generatedAt))) {
    fail(file, "missing or invalid generatedAt");
  }
  const metrics = report.metrics;
  if (!metrics || typeof metrics !== "object" || Object.keys(metrics).length < 5) {
    fail(file, "metrics object missing or too small");
  }
  if (file.endsWith("-full.json")) {
    const setup = report.summary?.setup ?? {};
    const drc = report.summary?.drc ?? {};
    const lvs = report.summary?.lvs ?? {};
    if (Object.keys(setup).length === 0) fail(file, "full-flow report without setup data");
    if (Object.keys(drc).length === 0) fail(file, "full-flow report without DRC data");
    if (Object.keys(lvs).length === 0) fail(file, "full-flow report without LVS data");
  }
}

if (failed) {
  console.error(`[FAIL] ${failed} report artifact(s) invalid`);
  process.exit(1);
}
console.log(`[OK] ${files.length} openlane report artifacts valid`);
