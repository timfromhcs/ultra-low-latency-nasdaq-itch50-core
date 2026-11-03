// =============================================================================
// File: scripts/rtl_wasm_equiv.mjs
// Description: Compare the Verilator RTL and the WebAssembly twin on the SAME
//              ITCH stream, record by record.
//
//   node scripts/rtl_wasm_equiv.mjs [--rtl reports/rtl_records.bin]
//
// The RTL dump is produced by `make sim VECTORS=tb/vectors` plus the --dump
// invocation below (or by the script if --run is passed).
// =============================================================================
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const argVal = (name, dflt) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
};

const streamPath = path.resolve(root, argVal("stream", "tb/vectors/stream.bin"));
const dumpPath = path.resolve(root, argVal("rtl", "reports/rtl_records.bin"));
const wasmPath = path.resolve(root, "web/wasm/chiplab_core.wasm");

if (args.includes("--run")) {
  console.log("[equiv] running the RTL sim (make sim) ...");
  execFileSync("make", ["sim", "VECTORS=tb/vectors"], { cwd: root, stdio: "inherit" });
  const bin = "/tmp/itch_workspace/tb/obj_dir/Vultra_low_latency_nasdaq_itch50_cutthrough";
  execFileSync(bin, ["--vectors", "vectors", "--dump", dumpPath], {
    cwd: "/tmp/itch_workspace/tb",
    stdio: "inherit",
  });
}

if (!fs.existsSync(dumpPath)) {
  console.error(`[equiv] missing RTL dump: ${dumpPath}\n        run: node scripts/rtl_wasm_equiv.mjs --run`);
  process.exit(2);
}

const stream = fs.readFileSync(streamPath);
const rtl = fs.readFileSync(dumpPath);
const REC = 80;
if (rtl.length % REC !== 0) {
  console.error(`[equiv] RTL dump size ${rtl.length} is not a multiple of ${REC}`);
  process.exit(2);
}

const wasmBytes = fs.readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const e = instance.exports;
const mem = () => new Uint8Array(e.memory.buffer);
const streamCap = 96 * 1024 * 1024;
const outCap = 192 * 1024 * 1024;
const streamPtr = e.alloc(streamCap);
const outPtr = e.alloc(outCap);
mem().set(stream, streamPtr);
const n = e.run_chip(1, streamPtr, stream.length, outPtr, outCap);
if (!n) {
  console.error("[equiv] WASM run_chip returned 0 (capacity)");
  process.exit(1);
}
const wasm = mem().slice(outPtr + 48, outPtr + n);

const rtlRecs = rtl.length / REC;
const wasmRecs = wasm.length / REC;
console.log(`[equiv] stream ${stream.length} B · RTL ${rtlRecs} records · WASM ${wasmRecs} records`);

if (rtlRecs !== wasmRecs) {
  console.error(`[equiv] record count mismatch: RTL ${rtlRecs} vs WASM ${wasmRecs}`);
  process.exit(1);
}

const fields = [
  ["type", 0, 1], ["flags", 1, 1], ["len", 2, 1],
  ["locate", 4, 2], ["tracking", 6, 2],
  ["timestamp", 8, 6], ["ref", 16, 8], ["nref", 24, 8], ["shares", 32, 8],
  ["price", 40, 4], ["side", 44, 1], ["printable", 45, 1], ["event", 46, 1],
  ["match", 48, 8], ["stock", 56, 8], ["mpid", 64, 4], ["refValue", 68, 4],
  ["checksum", 72, 4],
];
function le(buf, off, size) {
  let v = 0n;
  for (let i = size - 1; i >= 0; i--) v = (v << 8n) | BigInt(buf[off + i]);
  return v;
}
for (let i = 0; i < rtlRecs; i++) {
  const a = i * REC;
  for (const [name, off, size] of fields) {
    const x = le(rtl, a + off, size);
    const y = le(wasm, a + off, size);
    if (x !== y) {
      console.error(`[equiv] record ${i} field ${name}: RTL ${x} vs WASM ${y}`);
      process.exit(1);
    }
  }
}
console.log("[equiv] RTL == WASM on the same stream (every canonical field) PASS");
