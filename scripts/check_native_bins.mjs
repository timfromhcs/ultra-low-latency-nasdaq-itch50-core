// =============================================================================
// File: scripts/check_native_bins.mjs
// Description: Compare the native GPU bins with the CPU reference.
// Run: node scripts/check_native_bins.mjs
// =============================================================================
import fs from "node:fs";

const rec = fs.readFileSync("reports/native_records.bin");
const nativeBuf = fs.readFileSync("reports/native_bins.bin");
const native = new Uint32Array(nativeBuf.buffer, nativeBuf.byteOffset, nativeBuf.length / 4);
const n = rec.length / 16;
const u32 = new Uint32Array(rec.buffer, rec.byteOffset, rec.length / 4);
let min = 0xffffffff, max = 0;
for (let i = 0; i < n; i++) {
  const p = u32[i * 4 + 1];
  if (p && p < min) min = p;
  if (p > max) max = p;
}
if (min === 0xffffffff) min = 0;
if (max <= min) max = min + 1;
const bins = new Uint32Array(128), hist = new Uint32Array(64);
for (let i = 0; i < n; i++) {
  const p = u32[i * 4 + 1];
  if (p >= min && p <= max) {
    let b = Math.floor(((p - min) * 128) / Math.max(1, max - min));
    if (b > 127) b = 127;
    bins[b]++;
  }
  hist[Math.min(63, u32[i * 4 + 3] & 0xffff)]++;
}
let bad = 0;
for (let i = 0; i < 128; i++) if (bins[i] !== native[i]) bad++;
for (let i = 0; i < 64; i++) if (hist[i] !== native[128 + i]) bad++;
const sum = Array.from(native).reduce((a, b) => a + b, 0);
console.log(`native bins: ${n} records, sum=${sum}, mismatches=${bad}`);
if (bad) {
  for (let i = 0; i < 128; i++) if (bins[i] !== native[i]) { console.log(`bin ${i}: cpu=${bins[i]} gpu=${native[i]}`); if (i > 10) break; }
  process.exit(1);
}
