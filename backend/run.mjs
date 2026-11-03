#!/usr/bin/env node
// =============================================================================
// File: backend/run.mjs
// Description: CLI for the local chip lab.
//
//   node backend/run.mjs --chip 1 --count 1000000
//   node backend/run.mjs --compare --count 1000000
//   node backend/run.mjs --chip 6 --mode 1 --count 250000
// =============================================================================
import { loadCore, CHIPS, decodeRecord } from "./wasm.mjs";

function arg(name, dflt) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : dflt;
}
const flag = (name) => process.argv.includes(`--${name}`);

const count = Number(arg("count", "100000"));
const seed = Number(arg("seed", "1337"));
const chip = Number(arg("chip", "1"));
const mode = Number(arg("mode", "0"));
const core = await loadCore();
const stream = core.generate(count, mode, seed);

if (flag("compare")) {
  const rows = core.compare(stream);
  console.log(`\nChipLab compare — ${count.toLocaleString()} messages, seed ${seed}, ${stream.len.toLocaleString()} bytes\n`);
  console.log("chip                 msgs     cycles     Gbps    Msg/s   lat(ns)   errors  status");
  console.log("-".repeat(86));
  for (const r of rows) {
    console.log(
      `${r.name.padEnd(20)} ${String(r.messages).padStart(8)} ${String(r.cycles).padStart(10)} ` +
      `${r.gbps.toFixed(2).padStart(8)} ${r.mps.toFixed(2).padStart(8)} ${r.latencyNs.toFixed(1).padStart(8)} ` +
      `${String(r.errors).padStart(8)}  ${r.status}`
    );
  }
  console.log("");
} else {
  const r = core.run(chip, stream);
  const meta = CHIPS.find((c) => c.id === chip) || CHIPS[1];
  const ns = Math.max(1, r.header.cycles) * 3.1;
  console.log(`\nchip: ${meta.name} (#${chip})`);
  console.log(`mode: ${mode}  seed: ${seed}  stream: ${stream.len.toLocaleString()} bytes`);
  console.log(`messages: ${r.header.count.toLocaleString()}  corrupt: ${r.header.corrupt.toLocaleString()}  frames: ${r.header.frames.toLocaleString()}`);
  console.log(`cycles: ${r.header.cycles.toLocaleString()}  time: ${(ns / 1000).toFixed(3)} µs  throughput: ${((r.header.bytesIn * 8) / (ns * 1e-9) / 1e9).toFixed(2)} Gbps`);
  const sample = Number(arg("sample", "8"));
  for (let i = 0, off = 0; i < sample && off + 80 <= r.records.length; i++, off += 80) {
    const rec = decodeRecord(r.records, off);
    console.log(`  ${String(i).padStart(4)} ${rec.typeChar} loc=${String(rec.locate).padStart(4)} len=${String(rec.msgLen).padStart(2)} ` +
      `sym=${(rec.symbol || "-").padEnd(8)} px=${String(rec.price).padStart(8)} sh=${String(rec.shares).padStart(8)} ` +
      `lat=${rec.latency}c ${rec.isCorrupt ? "CORRUPT" : rec.isReference ? "ref" : "trade"}`);
  }
  console.log("");
}
core.dispose();
