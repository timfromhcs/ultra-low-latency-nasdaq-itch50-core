// =============================================================================
// File: web/core.js
// Description: Browser-side WASM loader, record decoder and chip comparison.
//              Shared by the Worker (and conceptually by the Node backend).
// =============================================================================
export const RECORD_SIZE = 80;
export const HEADER_SIZE = 48;
export const MAGIC = 0x42414c43;

export const CHIPS = [
  { id: 0, key: "scalar", name: "Scalar reference", family: "software", latency: 0, note: "Golden model, no pipeline" },
  { id: 1, key: "rtl-1c", name: "ITCH-50 v2", family: "rtl", latency: 1, note: "128-bit, 1-cycle egress after window" },
  { id: 2, key: "rtl-2c-safe", name: "ITCH-50 safe", family: "rtl", latency: 2, note: "Timing-closed variant, no async bypass" },
  { id: 3, key: "rival-3c", name: "Enyx-class", family: "rival", latency: 3, note: "Commercial-class 3-cycle model" },
  { id: 4, key: "rival-2c", name: "NovaSparks-class", family: "rival", latency: 2, note: "2-cycle parser model" },
  { id: 5, key: "lossy", name: "Lossy admin-drop", family: "negative", latency: 1, note: "Drops reference data: must fail" },
  { id: 6, key: "mold-128", name: "MoldUDP64 front-end", family: "rtl", latency: 3, note: "L2/L3/L4 + Mold + gap tracking" },
  { id: 7, key: "book-128", name: "Parser + top-of-book", family: "rtl", latency: 2, note: "Parse-to-book stage" },
];

export function chipById(id) {
  return CHIPS.find((c) => c.id === Number(id)) || CHIPS[1];
}

function u16(b, o) { return b[o] | (b[o + 1] << 8); }
function u32(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }
function u64(b, o) {
  let v = 0n;
  for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(b[o + i]);
  return v;
}
function u64n(b, o) { return Number(u64(b, o)); }

export function decodeHeader(b, off = 0) {
  return {
    magic: u32(b, off), chip: u32(b, off + 4), count: u64n(b, off + 8),
    cycles: u64n(b, off + 16), bytesIn: u64n(b, off + 24),
    corrupt: u64n(b, off + 32), frames: u64n(b, off + 40),
  };
}

export function decodeRecord(b, off) {
  const flags = b[off + 1];
  const stock = u64(b, off + 56);
  const bytes = [];
  for (let i = 7; i >= 0; i--) bytes.push(Number((stock >> BigInt(i * 8)) & 0xffn));
  const symbol = new TextDecoder("ascii").decode(new Uint8Array(bytes)).replace(/\0+$/, "").trimEnd();
  return {
    type: b[off], typeChar: b[off] >= 32 && b[off] < 127 ? String.fromCharCode(b[off]) : ".",
    flags, isTrade: !!(flags & 1), isReference: !!(flags & 2), isCorrupt: !!(flags & 4),
    msgLen: b[off + 2], locate: u16(b, off + 4), tracking: u16(b, off + 6),
    timestamp: u64n(b, off + 8), orderRef: u64(b, off + 16).toString(),
    newOrderRef: u64(b, off + 24).toString(), shares: Number(u64(b, off + 32)),
    price: u32(b, off + 40), side: b[off + 44] ? String.fromCharCode(b[off + 44]) : "",
    printable: b[off + 45], eventCode: b[off + 46], matchNumber: u64(b, off + 48).toString(),
    stock: stock.toString(), symbol, mpid: u32(b, off + 64), refValue: u32(b, off + 68), checksum: u32(b, off + 72),
    latency: u16(b, off + 76),
  };
}

export function recordsEqual(g, gi, c, ci) {
  for (let i = 0; i < 76; i++) if (g[gi + i] !== c[ci + i]) return false;
  return true;
}

export function compareRuns(golden, r) {
  let j = 0, missing = 0, extra = 0;
  const g = golden.records, c = r.records;
  for (let i = 0; i + RECORD_SIZE <= g.length; i += RECORD_SIZE) {
    let found = -1;
    const limit = Math.min(c.length - RECORD_SIZE, j + RECORD_SIZE * 12);
    for (let k = j; k <= limit; k += RECORD_SIZE) {
      if (recordsEqual(g, i, c, k)) { found = k; break; }
    }
    if (found < 0) { missing++; }
    else {
      missing += (found - j) / RECORD_SIZE;
      j = found + RECORD_SIZE;
    }
  }
  extra = Math.max(0, (c.length - j) / RECORD_SIZE);
  return { errors: missing + extra, missing, extra };
}

export class Core {
  constructor(instance, bytes) {
    this.instance = instance;
    this.exports = instance.exports;
    this.wasmBytes = bytes;
    this.streamCap = 96 * 1024 * 1024;
    this.outCap = 192 * 1024 * 1024;
    this.streamPtr = this.exports.alloc(this.streamCap);
    this.outPtr = this.exports.alloc(this.outCap);
  }
  get mem() { return new Uint8Array(this.exports.memory.buffer); }
  version() { return this.exports.version(); }
  generate(count, mode, seed) {
    const n = this.exports.generate_stream(BigInt(seed), count, mode, this.streamPtr, this.streamCap);
    if (!n) throw new Error("generate_stream capacity");
    return { ptr: this.streamPtr, len: n, data: new Uint8Array(this.mem.subarray(this.streamPtr, this.streamPtr + n)) };
  }
  run(chip, stream) {
    const n = this.exports.run_chip(chip, stream.ptr, stream.len, this.outPtr, this.outCap);
    if (!n) throw new Error("run_chip capacity");
    const mem = this.mem;
    return {
      header: decodeHeader(mem, this.outPtr),
      records: new Uint8Array(mem.subarray(this.outPtr + HEADER_SIZE, this.outPtr + n)),
      bytes: n,
    };
  }
  buildBook(stream) {
    const n = this.exports.build_book(stream.ptr, stream.len, this.outPtr, this.outCap);
    const mem = this.mem;
    const out = [];
    for (let off = 0; off < n; off += 32) {
      out.push({
        locate: u16(mem, this.outPtr + off), bid: u32(mem, this.outPtr + off + 4),
        ask: u32(mem, this.outPtr + off + 8), last: u32(mem, this.outPtr + off + 12),
        volume: u64n(mem, this.outPtr + off + 16), orders: u32(mem, this.outPtr + off + 24),
      });
    }
    return out;
  }
  dispose() {
    this.exports.dealloc(this.streamPtr, this.streamCap);
    this.exports.dealloc(this.outPtr, this.outCap);
  }
}

export async function loadCore(url) {
  const res = await fetch(url, { cache: "no-cache" });
  if (!res.ok) throw new Error(`WASM fetch failed: ${res.status}`);
  const bytes = await res.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return new Core(instance, bytes.byteLength);
}
