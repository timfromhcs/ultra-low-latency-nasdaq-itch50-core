// =============================================================================
// File: api/_core.mjs
// Description: Shared serverless helpers for the Vercel deployment. Static-first:
//              user data stays in the browser (OPFS); these endpoints are
//              stateless compute only.
// =============================================================================
import { loadCore, CHIPS, decodeRecord, hostInfo, countRecordErrors } from "../backend/wasm.mjs";

let corePromise = null;
export function getCore() {
  if (!corePromise) corePromise = loadCore();
  return corePromise;
}

export function summarize(h, streamBytes) {
  const cycles = Math.max(1, h.cycles), ns = cycles * 3.1;
  return {
    chip: h.chip, messages: h.count, cycles, ns,
    gbps: (h.bytesIn * 8) / (ns * 1e-9) / 1e9,
    mps: h.count / (ns * 1e-9) / 1e6,
    bytesIn: h.bytesIn, streamBytes, corrupt: h.corrupt, frames: h.frames,
  };
}

export async function run(body = {}) {
  const core = await getCore();
  const count = Math.max(1, Math.min(2_000_000, Number(body.count) || 100000));
  const chip = Math.max(0, Math.min(7, Number(body.chip ?? 1)));
  const seed = Math.max(0, Number(body.seed) || 1337);
  const mode = Math.max(0, Math.min(2, Number(body.mode) || 0));
  const stream = core.generate(count, mode, seed);
  const r = core.run(chip, stream);
  const records = [];
  for (let i = 0, off = 0; i < 40 && off + 80 <= r.records.length; i++, off += 80) records.push(decodeRecord(r.records, off));
  const errors = chip === 0 ? 0 : countRecordErrors(core.run(0, stream), r);
  return { ok: true, ...summarize(r.header, stream.len), errors, seed, mode, records, book: core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 32), host: hostInfo() };
}

export async function compare(body = {}) {
  const core = await getCore();
  const count = Math.max(1, Math.min(1_000_000, Number(body.count) || 100000));
  const seed = Math.max(0, Number(body.seed) || 1337);
  const stream = core.generate(count, 0, seed);
  return { ok: true, seed, streamBytes: stream.len, rows: core.compare(stream), host: hostInfo(), chips: CHIPS };
}

export async function book(body = {}) {
  const core = await getCore();
  const count = Math.max(1, Math.min(1_000_000, Number(body.count) || 100000));
  const seed = Math.max(0, Number(body.seed) || 1337);
  const stream = core.generate(count, 0, seed);
  return { ok: true, seed, streamBytes: stream.len, book: core.buildBook(stream) };
}

export function health() {
  return { ok: true, service: "chiplab-vercel", version: "0.3.0", chips: CHIPS, host: hostInfo(), persistence: "browser-local (OPFS/IndexedDB)" };
}
