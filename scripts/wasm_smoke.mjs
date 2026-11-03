// =============================================================================
// File: scripts/wasm_smoke.mjs
// Description: Node-side smoke test of the WebAssembly chip-lab core.
// Run: node scripts/wasm_smoke.mjs
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const wasmPath = path.resolve(here, "../web/wasm/chiplab_core.wasm");
const bytes = fs.readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const e = instance.exports;
const mem = () => new Uint8Array(e.memory.buffer);

function write(u8, ptr, data) {
  u8.set(data, ptr);
}
function u64(u8, off) {
  let v = 0n;
  for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(u8[off + i]);
  return v;
}
function u32(u8, off) {
  return (u8[off] | (u8[off + 1] << 8) | (u8[off + 2] << 16) | (u8[off + 3] << 24)) >>> 0;
}
function header(u8, ptr) {
  return {
    magic: u32(u8, ptr).toString(16),
    chip: u32(u8, ptr + 4),
    count: Number(u64(u8, ptr + 8)),
    cycles: Number(u64(u8, ptr + 16)),
    bytes_in: Number(u64(u8, ptr + 24)),
    corrupt: Number(u64(u8, ptr + 32)),
    frames: Number(u64(u8, ptr + 40)),
  };
}

const STREAM_CAP = 64 * 1024 * 1024;
const OUT_CAP = 128 * 1024 * 1024;
const streamPtr = e.alloc(STREAM_CAP);
const outPtr = e.alloc(OUT_CAP);

function generate(count, mode, seed = 1337) {
  const n = e.generate_stream(BigInt(seed), count, mode, streamPtr, STREAM_CAP);
  const u8 = mem();
  return { ptr: streamPtr, len: n, data: u8.slice(streamPtr, streamPtr + n) };
}

function run(chip, stream) {
  const n = e.run_chip(chip, stream.ptr, stream.len, outPtr, OUT_CAP);
  const u8 = mem();
  const h = header(u8, outPtr);
  return { n, h, records: u8.slice(outPtr + 48, outPtr + n) };
}

const raw = generate(10000, 0);
const golden = run(0, raw);
const rtl = run(1, raw);
const lossy = run(5, raw);

let byteEqual = golden.records.length === rtl.records.length;
if (byteEqual) {
  for (let i = 0; i < golden.records.length; i++) {
    const off = i * 80;
    // Ignore the per-record latency field at +76..78.
    for (let b = 0; b < 76; b++) {
      if (golden.records[off + b] !== rtl.records[off + b]) { byteEqual = false; break; }
    }
    if (!byteEqual) break;
  }
}

const mold = generate(10000, 1);
const moldChip = run(6, mold);
const eth = generate(10000, 2);
const ethChip = run(6, eth);

console.log(JSON.stringify({
  version: "0x" + e.version().toString(16),
  wasm_bytes: bytes.length,
  raw: { bytes: raw.len, ...golden.h },
  rtl1c: rtl.h,
  lossy: lossy.h,
  golden_vs_rtl1c_records_equal: byteEqual,
  mold: { stream_bytes: mold.len, ...moldChip.h },
  ethernet: { stream_bytes: eth.len, ...ethChip.h },
}, null, 2));

// Leave a fixture for the Python cross-check.
fs.mkdirSync(path.resolve(here, "../reports"), { recursive: true });
fs.writeFileSync(path.resolve(here, "../reports/wasm_stream.bin"), raw.data);
fs.writeFileSync(path.resolve(here, "../reports/wasm_records.bin"), golden.records);
console.log("wrote reports/wasm_stream.bin and reports/wasm_records.bin");

e.dealloc(streamPtr, STREAM_CAP);
e.dealloc(outPtr, OUT_CAP);
