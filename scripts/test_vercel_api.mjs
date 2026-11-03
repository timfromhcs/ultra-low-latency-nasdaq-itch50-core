// =============================================================================
// File: scripts/test_vercel_api.mjs
// Description: Invoke the Vercel serverless handlers with a mock req/res.
// Run: node scripts/test_vercel_api.mjs
// =============================================================================
import health from "../api/health.mjs";
import run from "../api/run.mjs";
import compare from "../api/compare.mjs";

function mock(body = {}) {
  const out = { code: 200, headers: {}, body: null };
  const res = {
    setHeader(k, v) { out.headers[k] = v; },
    status(c) { out.code = c; return this; },
    json(o) { out.body = o; return this; },
    end() { return this; },
  };
  return { req: { method: "POST", body }, res, out };
}

const h = mock(); health(h.req, h.res);
if (!h.out.body.ok || h.out.body.chips.length !== 8) throw new Error("health failed");
console.log("health:", h.out.body.service, h.out.body.chips.length, "chips");

const r = mock({ chip: 1, count: 5000, seed: 7 }); await run(r.req, r.res);
if (!r.out.body.ok || r.out.body.messages !== 5000) throw new Error("run failed");
console.log("run:", r.out.body.messages, r.out.body.gbps.toFixed(2), "Gbps");

const c = mock({ count: 5000, seed: 7 }); await compare(c.req, c.res);
const lossy = c.out.body.rows.find((x) => x.key === "lossy");
if (!c.out.body.ok || lossy.status !== "FAIL") throw new Error("compare failed");
console.log("compare:", c.out.body.rows.map((x) => x.key + ":" + x.status).join(" "));
console.log("VERCEL API SMOKE PASS");
