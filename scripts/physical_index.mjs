// =============================================================================
// File: scripts/physical_index.mjs
// Description: Aggregate every reports/openlane_*.json into one machine-readable
//   index (reports/physical.json) plus a short console table. The index is the
//   single source of truth for "what physical evidence exists and what it says".
// Run: node scripts/physical_index.mjs
// =============================================================================
import fs from "node:fs";
import path from "node:path";

const dir = "reports";
const files = fs
  .readdirSync(dir)
  .filter((f) => f.startsWith("openlane_") && f.endsWith(".json"))
  .sort();

const rows = [];
for (const file of files) {
  let report;
  try {
    report = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
  } catch {
    continue;
  }
  const m = report.metrics ?? {};
  const s = report.summary ?? {};
  const drc = s.drc ?? {};
  const lvs = s.lvs ?? {};
  const num = (v) => (typeof v === "number" ? v : null);
  const isFull =
    "magic__drc_error__count" in m ||
    "klayout__drc_error__count" in m ||
    "design__lvs_error__count" in m;
  rows.push({
    tag: report.tag ?? file.replace(/^openlane_|\.json$/g, ""),
    report: file,
    kind: isFull ? "full" : "sta-only",
    clockPeriodNs: report.derived?.clockPeriodNs ?? null,
    fmaxMHz: report.derived?.fmaxEstimateMHz ?? null,
    timingClosed: report.derived?.timingClosed ?? null,
    setupWs: num(m.timing__setup__ws),
    holdWs: num(m.timing__hold__ws),
    magicDrc: num(m.magic__drc_error__count),
    klayoutDrc: num(m.klayout__drc_error__count),
    lvsErrors: num(m.design__lvs_error__count),
    stdcells: num(m.design__instance__count__stdcell),
    caveat: report.note ?? null,
  });
}

fs.mkdirSync("reports", { recursive: true });
fs.writeFileSync(
  "reports/physical.json",
  JSON.stringify({ generatedAt: new Date().toISOString(), flows: rows }, null, 2) + "\n",
);

const fmt = (v) => (v === null || v === undefined ? "-" : String(v));
console.log(`[OK] ${rows.length} physical flows -> reports/physical.json`);
for (const r of rows) {
  const mark = r.caveat ? " *" : "";
  console.log(
    `  ${r.tag.padEnd(22)} ${r.kind.padEnd(9)} clk=${fmt(r.clockPeriodNs)}ns fmax=${fmt(r.fmaxMHz)}MHz ` +
      `setup=${fmt(r.setupWs)} hold=${fmt(r.holdWs)} ` +
      `magic=${fmt(r.magicDrc)} klayout=${fmt(r.klayoutDrc)} lvs=${fmt(r.lvsErrors)} ` +
      `cells=${fmt(r.stdcells)}${mark}`,
  );
}
if (rows.some((r) => r.caveat)) {
  console.log("  * see the report's note: its aggregate setup metric is not the signoff corner");
}
