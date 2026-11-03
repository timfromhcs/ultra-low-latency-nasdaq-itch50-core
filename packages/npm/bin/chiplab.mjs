#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadCoreFromFile, CHIPS, decodeRecord } from "../index.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const wasm = path.resolve(here, "../wasm/chiplab_core.wasm");
const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i >= 0 ? process.argv[i + 1] : d; };
const has = (n) => process.argv.includes(`--${n}`);
const count = Number(arg("count", "100000"));
const seed = Number(arg("seed", "1337"));
const chip = Number(arg("chip", "1"));

const core = await loadCoreFromFile(wasm);
const stream = core.generate(count, 0, seed);
if (has("compare")) {
  const rows = core.compare(stream);
  console.log(`chip                 msgs     cycles     Gbps    Msg/s   lat(ns)  errors  status`);
  for (const r of rows) {
    console.log(`${r.name.padEnd(20)} ${String(r.messages).padStart(8)} ${String(r.cycles).padStart(10)} ${r.gbps.toFixed(2).padStart(8)} ${r.mps.toFixed(2).padStart(8)} ${r.latencyNs.toFixed(1).padStart(8)} ${String(r.errors).padStart(7)}  ${r.status}`);
  }
} else {
  const r = core.run(chip, stream);
  const meta = CHIPS.find((c) => c.id === chip) || CHIPS[1];
  console.log(`${meta.name}: ${r.header.count} messages, ${r.header.cycles} cycles, ${((r.header.bytesIn * 8) / (r.header.cycles * 3.1e-9) / 1e9).toFixed(2)} Gbps`);
  for (let i = 0, off = 0; i < 5 && off < r.records.length; i++, off += 80) {
    const rec = decodeRecord(r.records, off);
    console.log(`  ${rec.typeChar} ${rec.isCorrupt ? "CORRUPT" : rec.symbol || "loc:" + rec.locate} price=${rec.price} shares=${rec.shares}`);
  }
}
core.dispose();
