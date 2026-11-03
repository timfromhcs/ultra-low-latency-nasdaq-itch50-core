// =============================================================================
// File: scripts/export_records.mjs
// Description: Export compact 16-byte records for the native Vulkan runner.
// Run: node scripts/export_records.mjs --count 1000000
// =============================================================================
import fs from "node:fs";
import { loadCore } from "../backend/wasm.mjs";

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i >= 0 ? process.argv[i + 1] : d; };
const count = Number(arg("count", "1000000"));
const seed = Number(arg("seed", "1337"));
const core = await loadCore();
const stream = core.generate(count, 0, seed);
const r = core.run(1, stream);
const out = new Uint32Array(r.header.count * 4);
let p = 0;
for (let i = 0, off = 0; i < r.header.count && off + 80 <= r.records.length; i++, off += 80) {
  const b = r.records;
  const u16 = (o) => b[o] | (b[o + 1] << 8);
  const u32 = (o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
  let shares = 0n;
  for (let k = 7; k >= 0; k--) shares = (shares << 8n) | BigInt(b[off + 32 + k]);
  out[p++] = (u16(off + 4) | (b[off] << 16) | (b[off + 1] << 24)) >>> 0;
  out[p++] = u32(off + 40);
  out[p++] = Number(shares & 0xffffffffn);
  out[p++] = (u16(off + 76) | (b[off + 2] << 16)) >>> 0;
}
fs.mkdirSync("reports", { recursive: true });
fs.writeFileSync("reports/native_records.bin", Buffer.from(out.buffer));
console.log(`wrote reports/native_records.bin: ${r.header.count} records, ${out.byteLength} bytes`);
