// =============================================================================
// File: scripts/openlane_summary.mjs
// Description: Summarize a LibreLane/OpenLane run into a small committed JSON.
//   Usage: node scripts/openlane_summary.mjs [run-dir]
//   Default: newest directory under openlane/runs that has a metrics.json.
//   Only the summary is written to reports/; the run directory stays ignored.
// =============================================================================
import fs from "node:fs";
import path from "node:path";

const runsRoot = "openlane/runs";

function newestRun() {
  if (!fs.existsSync(runsRoot)) return null;
  const dirs = fs
    .readdirSync(runsRoot, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => path.join(runsRoot, d.name))
    .filter(
      (d) =>
        fs.existsSync(path.join(d, "metrics.json")) ||
        fs.existsSync(path.join(d, "final", "metrics.json")),
    )
    .map((d) => ({ d, t: fs.statSync(d).mtimeMs }))
    .sort((a, b) => b.t - a.t);
  return dirs[0]?.d ?? null;
}

const runDir = process.argv[2] || newestRun();
if (!runDir) {
  console.error("[FAIL] no LibreLane run with metrics.json found");
  process.exit(2);
}

const metricsPath = ["final/metrics.json", "metrics.json"]
  .map((p) => path.join(runDir, p))
  .find((p) => fs.existsSync(p));
if (!metricsPath) {
  console.error(`[FAIL] no metrics.json in ${runDir}`);
  process.exit(2);
}

const metrics = JSON.parse(fs.readFileSync(metricsPath, "utf8"));
const tag = path.basename(runDir);

// Derive an Fmax estimate from the worst setup slack (informative only).
let clockPeriod = null;
const resolvedPath = path.join(runDir, "resolved.json");
if (fs.existsSync(resolvedPath)) {
  try {
    const resolved = JSON.parse(fs.readFileSync(resolvedPath, "utf8"));
    const p = resolved?.CLOCK_PERIOD ?? resolved?.config?.CLOCK_PERIOD;
    if (Number.isFinite(Number(p))) clockPeriod = Number(p);
  } catch {
    /* keep null */
  }
}

const ws = Number(metrics.timing__setup__ws);
const derived = {};
if (Number.isFinite(ws) && Number.isFinite(clockPeriod)) {
  const reachable = clockPeriod - ws; // ns per clock at the worst path
  derived.clockPeriodNs = clockPeriod;
  derived.fmaxEstimateMHz = reachable > 0 ? Number((1000 / reachable).toFixed(2)) : null;
  derived.timingClosed = ws >= 0;
}

// Select the fields that matter for a human summary, with tolerant matching
// (LibreLane renames metrics between versions).
const pick = (patterns) => {
  const out = {};
  for (const [k, v] of Object.entries(metrics)) {
    if (patterns.some((p) => p.test(k))) out[k] = v;
  }
  return out;
};

const summary = {
  dieBbox: pick([/^design__die__bbox$/]),
  coreBbox: pick([/^design__core__bbox$/]),
  instances: pick([/^design__instance__count/i]),
  area: pick([/^design__instance__area/i]),
  setup: pick([/^timing__setup__(ws|tns|wrst|skew)/i]),
  hold: pick([/^timing__hold__(ws|tns|wrst|skew)/i]),
  drc: pick([/drc/i]),
  lvs: pick([/lvs/i]),
  route: pick([/^route__/i]),
};

// Locate the worst-path report (prefer the ss corner) for publication.
function findFiles(root, name) {
  const hits = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name === name) hits.push(p);
    }
  };
  walk(root);
  return hits;
}

let worstPath = null;
const reports = findFiles(runDir, "max.rpt")
  .map((p) => ({ p, corner: p.includes("ss_") ? 0 : 1 }))
  .sort((a, b) => a.corner - b.corner);
if (reports.length) {
  const lines = fs.readFileSync(reports[0].p, "utf8").split(/\r?\n/).slice(0, 40);
  const grab = (re) => lines.map((l) => l.match(re)).find(Boolean)?.[1]?.trim();
  const startpoint = grab(/^Startpoint:\s+(.+)$/);
  const endpoint = grab(/^Endpoint:\s+(.+)$/);
  const pathGroup = grab(/^Path Group:\s+(.+)$/);
  if (startpoint || endpoint) {
    worstPath = {
      file: reports[0].p.replace(/\\/g, "/"),
      startpoint,
      endpoint,
      pathGroup,
      slackNs: Number.isFinite(ws) ? ws : null,
    };
  }
}

const report = {
  tag,
  generatedAt: new Date().toISOString(),
  metricsPath: metricsPath.replace(/\\/g, "/"),
  derived,
  worstPath,
  summary,
  metrics,
};
fs.mkdirSync("reports", { recursive: true });
const out = `reports/openlane_${tag}.json`;
fs.writeFileSync(out, JSON.stringify(report, null, 2) + "\n");

const fmt = (o) =>
  Object.keys(o).length ? Object.entries(o).map(([k, v]) => `  ${k} = ${v}`).join("\n") : "  (none)";
console.log(`[OK] ${tag}`);
console.log(`metrics: ${metricsPath}`);
console.log("die/core:\n" + fmt({ ...summary.dieBbox, ...summary.coreBbox }));
console.log("instances/area:\n" + fmt({ ...summary.instances, ...summary.area }));
console.log("setup:\n" + fmt(summary.setup));
console.log("hold:\n" + fmt(summary.hold));
console.log("drc:\n" + fmt(summary.drc));
console.log("lvs:\n" + fmt(summary.lvs));
console.log("derived:\n" + fmt(derived));
if (worstPath) console.log("worst path:\n" + fmt(worstPath));
console.log(`wrote ${out}`);
