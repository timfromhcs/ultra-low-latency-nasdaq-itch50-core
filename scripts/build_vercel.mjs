// =============================================================================
// File: scripts/build_vercel.mjs
// Description: Static-first Vercel build. Copies web/ to public/ so the app and
//              the WASM asset are served from the CDN; /api/* stays serverless
//              and stateless. User data never leaves the browser.
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const src = path.resolve(root, "web");
const out = path.resolve(root, "public");

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

function copy(dir, base = dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    const rel = path.relative(base, p);
    const dst = path.join(out, rel);
    if (e.isDirectory()) { fs.mkdirSync(dst, { recursive: true }); copy(p, base); }
    else { fs.mkdirSync(path.dirname(dst), { recursive: true }); fs.copyFileSync(p, dst); }
  }
}
copy(src);
fs.writeFileSync(path.join(out, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: /sitemap.xml\n");
fs.writeFileSync(path.join(out, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>/</loc></url><url><loc>/docs.html</loc></url></urlset>\n`);
console.log(`[vercel] wrote ${out} (${fs.readdirSync(out).length} top-level entries)`);
