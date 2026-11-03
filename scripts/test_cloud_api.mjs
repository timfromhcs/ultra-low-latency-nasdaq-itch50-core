// =============================================================================
// File: scripts/test_cloud_api.mjs
// Description: End-to-end local cloud gate. Starts the real backend on a free
//              port with a token, then verifies auth, revisions, conflicts,
//              traversal and the namespace cap.
//   node scripts/test_cloud_api.mjs
// =============================================================================
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "chiplab-cloud-"));
const port = 4300 + Math.floor(Math.random() * 400);
const base = `http://127.0.0.1:${port}`;
const token = "test-token";

const child = spawn(process.execPath, [
  path.join(root, "backend", "server.mjs"),
  "--port", String(port),
  "--token", token,
  "--data-dir", dataDir,
], { cwd: root, stdio: ["ignore", "pipe", "pipe"] });

let stderr = "";
child.stderr.on("data", (c) => { stderr += c; });

function fail(msg) {
  console.error(`CLOUD API FAIL: ${msg}`);
  try { child.kill(); } catch { /* already gone */ }
  process.exit(1);
}

async function waitReady() {
  for (let i = 0; i < 100; i++) {
    try {
      const r = await fetch(`${base}/api/cloud/info`);
      if (r.ok) return await r.json();
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  fail(`server did not start. stderr: ${stderr.slice(-400)}`);
}

async function req(method, url, body, useToken = true) {
  const headers = { "content-type": "application/json" };
  if (useToken) headers.authorization = `Bearer ${token}`;
  const r = await fetch(`${base}${url}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try { json = await r.json(); } catch { /* empty */ }
  return { status: r.status, json };
}

try {
  const info = await waitReady();
  if (info.service !== "chiplab-local-cloud") fail("wrong service name");
  if (!info.tokenRequired) fail("tokenRequired must be true");
  if (!Array.isArray(info.lanUrls)) fail("lanUrls missing");

  const noAuth = await req("PUT", "/api/store/default", { data: { runs: [1] } }, false);
  if (noAuth.status !== 401) fail(`no-auth PUT should be 401, got ${noAuth.status}`);

  const put1 = await req("PUT", "/api/store/default", { data: { runs: [1, 2, 3] }, expectedRevision: 0 });
  if (put1.status !== 200 || put1.json.revision !== 1) fail(`first PUT: ${put1.status} rev ${put1.json?.revision}`);

  const get1 = await req("GET", "/api/store/default");
  if (get1.status !== 200 || get1.json.data.runs.length !== 3) fail("GET after PUT returned wrong data");

  const conflict = await req("PUT", "/api/store/default", { data: { runs: [] }, expectedRevision: 0 });
  if (conflict.status !== 409) fail(`revision conflict should be 409, got ${conflict.status}`);

  const traversal = await req("GET", "/api/store/..%2f..%2fetc");
  if (traversal.status !== 400) fail(`traversal should be 400, got ${traversal.status}`);

  const invalid = await req("GET", "/api/store/bad!name");
  if (invalid.status !== 400) fail(`invalid namespace should be 400, got ${invalid.status}`);

  const big = await req("PUT", "/api/store/big", { data: { blob: "x".repeat(1024 * 1024 + 64) } });
  if (big.status !== 413) fail(`oversize should be 413, got ${big.status}`);

  const list = await req("GET", "/api/store");
  if (list.status !== 200 || !list.json.namespaces.includes("default")) fail("namespace list missing default");

  const del = await req("DELETE", "/api/store/default");
  if (del.status !== 200) fail("DELETE failed");

  const gone = await req("GET", "/api/store/default");
  if (gone.status !== 404) fail("deleted namespace should be 404");

  console.log(`CLOUD API PASS (port ${port}, auth, revisions, 409, 400, 413, list, delete)`);
} catch (e) {
  fail(String(e?.stack || e));
} finally {
  child.kill();
  fs.rmSync(dataDir, { recursive: true, force: true });
}
