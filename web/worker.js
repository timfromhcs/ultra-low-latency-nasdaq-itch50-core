// =============================================================================
// File: web/worker.js
// Description: ChipLab worker — owns WASM memory, generates streams, runs chip
//              models, packs records for WebGPU, and persists run summaries in
//              OPFS (IndexedDB fallback). No network, no cloud.
// =============================================================================
import { loadCore, decodeRecord, compareRuns, CHIPS } from "./core.js";

let core = null;
let ready = false;

function u16(b, o) { return b[o] | (b[o + 1] << 8); }
function u32(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }
function u64(b, o) {
  let v = 0n;
  for (let i = 7; i >= 0; i--) v = (v << 8n) | BigInt(b[o + i]);
  return Number(v);
}

function packForGpu(records, count) {
  const out = new Uint32Array(count * 4);
  let p = 0;
  for (let i = 0, off = 0; i < count && off + 80 <= records.length; i++, off += 80) {
    const type = records[off];
    const flags = records[off + 1];
    const locate = u16(records, off + 4);
    const price = u32(records, off + 40);
    const shares = Math.min(0xffffffff, u64(records, off + 32));
    const lat = u16(records, off + 76);
    const len = records[off + 2];
    out[p++] = (locate | (type << 16) | (flags << 24)) >>> 0;
    out[p++] = price >>> 0;
    out[p++] = shares >>> 0;
    out[p++] = (lat | (len << 16)) >>> 0;
  }
  return out;
}

function countTypes(records, count) {
  const types = new Uint32Array(256);
  for (let i = 0, off = 0; i < count && off + 80 <= records.length; i++, off += 80) types[records[off]]++;
  return types;
}

function latencyHist(records, count) {
  const hist = new Uint32Array(64);
  for (let i = 0, off = 0; i < count && off + 80 <= records.length; i++, off += 80) {
    hist[Math.min(63, u16(records, off + 76))]++;
  }
  return hist;
}

function summarize(header, streamBytes, wallMs) {
  const cycles = Math.max(1, header.cycles);
  const ns = cycles * 3.1;
  return {
    chip: header.chip,
    messages: header.count,
    cycles,
    ns,
    gbps: (header.bytesIn * 8) / (ns * 1e-9) / 1e9,
    mps: header.count / (ns * 1e-9) / 1e6,
    bytesIn: header.bytesIn,
    streamBytes,
    corrupt: header.corrupt,
    frames: header.frames,
    wallMs,
    timestamp: Date.now(),
  };
}

// ---------------------------------------------------------------------------
// Persistence: OPFS, IndexedDB fallback
// ---------------------------------------------------------------------------
const DB_NAME = "chiplab";
const STORE = "runs";

function idb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function saveRun(summary) {
  try {
    if (navigator.storage?.getDirectory) {
      const root = await navigator.storage.getDirectory();
      const dir = await root.getDirectoryHandle("runs", { create: true });
      const name = `run-${summary.timestamp}.json`;
      const fh = await dir.getFileHandle(name, { create: true });
      const w = await fh.createWritable();
      await w.write(JSON.stringify(summary));
      await w.close();
      return true;
    }
  } catch { /* fall through */ }
  try {
    const db = await idb();
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite");
      tx.objectStore(STORE).put(summary, String(summary.timestamp));
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    return true;
  } catch { return false; }
}

async function loadRuns() {
  const out = [];
  try {
    if (navigator.storage?.getDirectory) {
      const root = await navigator.storage.getDirectory();
      const dir = await root.getDirectoryHandle("runs", { create: true });
      for await (const [name, handle] of dir.entries()) {
        if (!name.endsWith(".json")) continue;
        const f = await handle.getFile();
        out.push(JSON.parse(await f.text()));
      }
    }
  } catch { /* ignore */ }
  if (!out.length) {
    try {
      const db = await idb();
      const rows = await new Promise((resolve, reject) => {
        const tx = db.transaction(STORE, "readonly");
        const req = tx.objectStore(STORE).getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      });
      out.push(...rows);
    } catch { /* ignore */ }
  }
  return out.sort((a, b) => b.timestamp - a.timestamp).slice(0, 8);
}

async function clearRuns() {
  try {
    if (navigator.storage?.getDirectory) {
      const root = await navigator.storage.getDirectory();
      const dir = await root.getDirectoryHandle("runs", { create: true });
      for await (const [name] of dir.entries()) if (name.endsWith(".json")) await dir.removeEntry(name);
    }
  } catch { /* ignore */ }
  try {
    const db = await idb();
    await new Promise((resolve) => {
      const tx = db.transaction(STORE, "readwrite");
      tx.objectStore(STORE).clear();
      tx.oncomplete = resolve;
    });
  } catch { /* ignore */ }
}

// ---------------------------------------------------------------------------
// Run / compare
// ---------------------------------------------------------------------------
function runOnce(chip, stream) {
  const r = core.run(chip, stream);
  const book = core.buildBook(stream).sort((a, b) => b.volume - a.volume).slice(0, 96);
  const sample = [];
  for (let i = 0, off = 0; i < 60 && off + 80 <= r.records.length; i++, off += 80) sample.push(decodeRecord(r.records, off));
  const count = r.header.count;
  return {
    header: r.header,
    records: r.records,
    book,
    sample,
    types: countTypes(r.records, count),
    latencyHist: latencyHist(r.records, count),
    gpu: packForGpu(r.records, count),
  };
}

async function handleRun(msg) {
  const t0 = performance.now();
  const stream = core.generate(msg.count, msg.mode || 0, msg.seed || 1337);
  const chip = msg.chip ?? 1;
  const run = runOnce(chip, stream);

  let errors = 0;
  if (msg.verify !== false) {
    const golden = chip === 0 ? run : runOnce(0, stream);
    errors = chip === 0 ? 0 : compareRuns(golden, run).errors;
  }

  const summary = summarize(run.header, stream.len, performance.now() - t0);
  summary.errors = errors;
  summary.chipKey = (CHIPS.find((c) => c.id === chip) || CHIPS[1]).key;
  if (msg.save !== false) await saveRun(summary);

  self.postMessage({
    type: "run",
    id: msg.id,
    summary,
    book: run.book,
    sample: run.sample,
    types: run.types,
    latencyHist: run.latencyHist,
    gpu: run.gpu.buffer,
    gpuCount: run.header.count,
    history: await loadRuns(),
  }, [run.gpu.buffer]);
}

async function handleCompare(msg) {
  const t0 = performance.now();
  const stream = core.generate(msg.count, 0, msg.seed || 1337);
  const golden = runOnce(0, stream);
  const rows = [];
  for (const chip of CHIPS) {
    const r = chip.id === 0 ? golden : runOnce(chip.id, stream);
    const cmp = chip.id === 0 ? { errors: 0 } : compareRuns(golden, r);
    const s = summarize(r.header, stream.len, 0);
    rows.push({ ...chip, ...s, errors: cmp.errors, status: cmp.errors === 0 ? "PASS" : "FAIL" });
  }
  self.postMessage({ type: "compare", id: msg.id, rows, wallMs: performance.now() - t0 });
}

self.onmessage = async (ev) => {
  const msg = ev.data;
  try {
    if (msg.type === "init") {
      core = await loadCore(msg.wasmUrl);
      ready = true;
      self.postMessage({ type: "ready", version: core.version(), wasmBytes: core.wasmBytes, chips: CHIPS });
      return;
    }
    if (!ready) throw new Error("worker not ready");
    if (msg.type === "run") return await handleRun(msg);
    if (msg.type === "compare") return await handleCompare(msg);
    if (msg.type === "history") return self.postMessage({ type: "history", history: await loadRuns() });
    if (msg.type === "clear") { await clearRuns(); return self.postMessage({ type: "cleared" }); }
  } catch (err) {
    self.postMessage({ type: "error", id: msg?.id, error: String(err?.stack || err) });
  }
};
