// =============================================================================
// File: backend/wasm.mjs
// Description: Node loader + record decoder for the ChipLab WebAssembly core.
//              The exact same .wasm artifact is used by the browser demo.
// =============================================================================
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const RECORD_SIZE = 80;
export const HEADER_SIZE = 48;
export const MAGIC = 0x42414c43;

export const CHIPS = [
  { id: 0, key: "scalar", name: "Scalar reference", family: "software", latency: 0, note: "Golden model, no pipeline" },
  { id: 1, key: "rtl-1c", name: "ITCH-50 v2 (RTL twin)", family: "rtl", latency: 1, note: "128-bit, 1-cycle egress after window" },
  { id: 2, key: "rtl-2c-safe", name: "ITCH-50 safe (2c)", family: "rtl", latency: 2, note: "Timing-closed variant, no async bypass" },
  { id: 3, key: "rival-3c", name: "Enyx-class (3c)", family: "rival", latency: 3, note: "Commercial-class 3-cycle parser model" },
  { id: 4, key: "rival-2c", name: "NovaSparks-class (2c)", family: "rival", latency: 2, note: "2-cycle parser model" },
  { id: 5, key: "lossy", name: "Lossy admin-drop", family: "negative", latency: 1, note: "Drops reference data: must fail correctness" },
  { id: 6, key: "mold-128", name: "MoldUDP64 front-end", family: "rtl", latency: 3, note: "L2/L3/L4 + Mold header + gap tracking" },
  { id: 7, key: "book-128", name: "Parser + top-of-book", family: "rtl", latency: 2, note: "Parse-to-book stage" },
];

let here = process.cwd();
try { here = path.dirname(fileURLToPath(import.meta.url)); } catch { /* SEA / CJS bundle */ }
const DEFAULT_WASM = path.resolve(here, "../web/wasm/chiplab_core.wasm");

function u16(b, o) { return b[o] | (b[o + 1] << 8); }
function u32(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }
function u64(b, o) {
  let v = 0n;
  for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(b[o + i]);
  return v;
}
function u64n(b, o) { return Number(u64(b, o)); }

export function decodeRecord(b, off) {
  const flags = b[off + 1];
  const stock = u64(b, off + 56);
  const bytes = [];
  for (let i = 7; i >= 0; i--) bytes.push(Number((stock >> BigInt(i * 8)) & 0xffn));
  const symbol = Buffer.from(bytes).toString("ascii").replace(/\0+$/, "").trimEnd();
  return {
    type: b[off],
    typeChar: b[off] >= 32 && b[off] < 127 ? String.fromCharCode(b[off]) : ".",
    flags,
    isTrade: !!(flags & 1),
    isReference: !!(flags & 2),
    isCorrupt: !!(flags & 4),
    msgLen: b[off + 2],
    locate: u16(b, off + 4),
    tracking: u16(b, off + 6),
    timestamp: u64n(b, off + 8),
    orderRef: u64(b, off + 16).toString(),
    newOrderRef: u64(b, off + 24).toString(),
    shares: Number(u64(b, off + 32)),
    price: u32(b, off + 40),
    side: b[off + 44] ? String.fromCharCode(b[off + 44]) : "",
    printable: b[off + 45],
    eventCode: b[off + 46],
    matchNumber: u64(b, off + 48).toString(),
    stock: stock.toString(),
    symbol,
    mpid: u32(b, off + 64),
    refValue: u32(b, off + 68),
    checksum: u32(b, off + 72),
    latency: u16(b, off + 76),
  };
}

export function decodeHeader(b, off) {
  return {
    magic: u32(b, off),
    chip: u32(b, off + 4),
    count: u64n(b, off + 8),
    cycles: u64n(b, off + 16),
    bytesIn: u64n(b, off + 24),
    corrupt: u64n(b, off + 32),
    frames: u64n(b, off + 40),
  };
}

export function countRecordErrors(golden, candidate) {
  let j = 0, missing = 0;
  const g = golden.records, c = candidate.records;
  for (let i = 0; i + RECORD_SIZE <= g.length; i += RECORD_SIZE) {
    let found = -1;
    const limit = Math.min(c.length - RECORD_SIZE, j + RECORD_SIZE * 12);
    for (let k = j; k <= limit; k += RECORD_SIZE) {
      if (recordsEqual(g.subarray(i, i + RECORD_SIZE), c.subarray(k, k + RECORD_SIZE))) { found = k; break; }
    }
    if (found < 0) missing++;
    else { missing += (found - j) / RECORD_SIZE; j = found + RECORD_SIZE; }
  }
  return missing + Math.max(0, (c.length - j) / RECORD_SIZE);
}

export function recordsEqual(g, c) {
  // Compare all canonical fields, ignoring the WASM-only latency field.
  for (let i = 0; i < 76; i++) {
    if (g[i] !== c[i]) return false;
  }
  return true;
}

export class ChipLabCore {
  constructor(instance, bytes) {
    this.instance = instance;
    this.exports = instance.exports;
    this.wasmBytes = bytes;
    this.streamCap = 96 * 1024 * 1024;
    this.outCap = 192 * 1024 * 1024;
    this.streamPtr = this.exports.alloc(this.streamCap);
    this.outPtr = this.exports.alloc(this.outCap);
    this.active = false;
  }

  get memory() { return new Uint8Array(this.exports.memory.buffer); }
  version() { return this.exports.version(); }

  generate(count, mode = 0, seed = 1337) {
    const n = this.exports.generate_stream(BigInt(seed), count, mode, this.streamPtr, this.streamCap);
    if (!n) throw new Error("generate_stream failed (capacity)");
    const data = Buffer.from(this.memory.subarray(this.streamPtr, this.streamPtr + n));
    return { ptr: this.streamPtr, len: n, data };
  }

  run(chip, stream) {
    const n = this.exports.run_chip(chip, stream.ptr, stream.len, this.outPtr, this.outCap);
    if (!n) throw new Error("run_chip failed (capacity)");
    const mem = this.memory;
    const header = decodeHeader(mem, this.outPtr);
    const records = Buffer.from(mem.subarray(this.outPtr + HEADER_SIZE, this.outPtr + n));
    return { header, records, bytes: n };
  }

  buildBook(stream) {
    const n = this.exports.build_book(stream.ptr, stream.len, this.outPtr, this.outCap);
    const mem = this.memory;
    const out = [];
    for (let off = 0; off < n; off += 32) {
      out.push({
        locate: u16(mem, this.outPtr + off),
        bid: u32(mem, this.outPtr + off + 4),
        ask: u32(mem, this.outPtr + off + 8),
        last: u32(mem, this.outPtr + off + 12),
        volume: u64n(mem, this.outPtr + off + 16),
        orders: u32(mem, this.outPtr + off + 24),
      });
    }
    return out;
  }

  compare(stream, goldenStream = stream) {
    const golden = this.run(0, goldenStream);
    const rows = [];
    for (const chip of CHIPS) {
      const r = this.run(chip.id, stream);
      let j = 0, missing = 0, mismatch = 0;
      for (let i = 0; i < golden.records.length; i += RECORD_SIZE) {
        if (j + RECORD_SIZE > r.records.length) { missing++; continue; }
        if (recordsEqual(golden.records.subarray(i, i + RECORD_SIZE),
                         r.records.subarray(j, j + RECORD_SIZE))) {
          j += RECORD_SIZE;
        } else {
          // Try to find the next matching record (lossy insertion).
          let found = -1;
          for (let k = j; k + RECORD_SIZE <= r.records.length && k < j + RECORD_SIZE * 8; k += RECORD_SIZE) {
            if (recordsEqual(golden.records.subarray(i, i + RECORD_SIZE),
                             r.records.subarray(k, k + RECORD_SIZE))) { found = k; break; }
          }
          if (found >= 0) { missing += (found - j) / RECORD_SIZE; j = found + RECORD_SIZE; }
          else { missing++; }
        }
      }
      const extra = (r.records.length - j) / RECORD_SIZE;
      const errors = missing + mismatch + extra;
      const cycles = Math.max(1, r.header.cycles);
      const ns = cycles * 3.1;
      rows.push({
        ...chip,
        messages: r.header.count,
        cycles,
        ns,
        gbps: (r.header.bytesIn * 8) / (ns * 1e-9) / 1e9,
        mps: r.header.count / (ns * 1e-9) / 1e6,
        corrupt: r.header.corrupt,
        errors,
        missing,
        extra,
        latencyNs: chip.latency * 3.1,
        status: errors === 0 ? "PASS" : "FAIL",
      });
    }
    return rows;
  }

  dispose() {
    this.exports.dealloc(this.streamPtr, this.streamCap);
    this.exports.dealloc(this.outPtr, this.outCap);
  }
}

export async function loadCoreFromBytes(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return new ChipLabCore(instance, bytes.length);
}

export async function loadCore(wasmPath = DEFAULT_WASM) {
  return loadCoreFromBytes(fs.readFileSync(wasmPath));
}

export function hostInfo() {
  const cpus = os.cpus();
  return {
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    cpu: cpus.length ? cpus[0].model.trim() : "unknown",
    cores: cpus.length,
    memoryGb: Math.round((os.totalmem() / 1024 ** 3) * 10) / 10,
    hostname: os.hostname(),
  };
}
