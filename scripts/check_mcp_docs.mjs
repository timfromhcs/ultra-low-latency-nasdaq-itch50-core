// =============================================================================
// File: scripts/check_mcp_docs.mjs
// Description: Keep docs/api.md in sync with the tools exposed by mcp/server.mjs.
//   Every `name: "chiplab.<tool>"` in the server must be documented, and the docs
//   must not name tools the server does not expose.
// Run: node scripts/check_mcp_docs.mjs
// =============================================================================
import fs from "node:fs";

const server = fs.readFileSync("mcp/server.mjs", "utf8");
const docs = fs.readFileSync("docs/api.md", "utf8");

const serverTools = new Set(
  [...server.matchAll(/name:\s*"(chiplab\.[a-z0-9_]+)"/g)].map((m) => m[1]),
);
const docTools = new Set(
  [...docs.matchAll(/^\|\s*`(chiplab\.[a-z0-9_]+)`/gm)].map((m) => m[1]),
);

const missingInDocs = [...serverTools].filter((t) => !docTools.has(t)).sort();
const missingInServer = [...docTools].filter((t) => !serverTools.has(t)).sort();

if (serverTools.size === 0) {
  console.error("[FAIL] no chiplab.* tools found in mcp/server.mjs");
  process.exit(2);
}

if (missingInDocs.length || missingInServer.length) {
  for (const t of missingInDocs) console.error(`[FAIL] ${t} is in the server but not in docs/api.md`);
  for (const t of missingInServer) console.error(`[FAIL] ${t} is in docs/api.md but not in the server`);
  process.exit(1);
}

console.log(`[OK] ${serverTools.size} MCP tools match docs/api.md`);
