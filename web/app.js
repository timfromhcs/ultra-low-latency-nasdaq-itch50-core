// =============================================================================
// File: web/app.js
// Description: ChipLab UI controller. Talks to the Worker, renders metrics,
//              tape, depth, histogram, comparison and local history.
// =============================================================================
import { CHIPS, chipById } from "./core.js";
import { GpuLab, drawHistogram } from "./gpu.js";

const $ = (id) => document.getElementById(id);
const fmt = (n, d = 0) => Number(n).toLocaleString("en-US", { maximumFractionDigits: d, minimumFractionDigits: d });
const usd = (p) => (p / 10000).toFixed(4);

const state = {
  worker: null,
  gpu: null,
  ready: false,
  busy: false,
  live: false,
  liveTimer: null,
  lastRun: null,
  runSeq: 0,
};

function setStatus(text, kind = "") {
  const el = $("status");
  el.textContent = text;
  el.className = `ds-supporting status ${kind}`;
}

function setBadge(id, text, kind = "outline") {
  const el = $(id);
  el.textContent = text;
  el.className = `ds-badge ${kind === "safe" ? "ds-badge-safe" : kind === "danger" ? "ds-badge-danger" : "ds-badge-outline"}`;
}

function fillChips() {
  const sel = $("chip");
  sel.innerHTML = "";
  for (const c of CHIPS) {
    const o = document.createElement("option");
    o.value = String(c.id);
    o.textContent = `${c.name} · ${c.latency}c`;
    sel.append(o);
  }
  sel.value = "1";
  renderContainers();
}

function renderContainers() {
  const box = $("containers-body");
  const active = Number($("chip").value);
  box.innerHTML = "";
  for (const c of CHIPS) {
    const row = document.createElement("div");
    row.className = `container-row ${c.id === active ? "active" : ""}`;
    row.innerHTML = `<span class="dot" aria-hidden="true"></span>
      <span class="name">${c.name}</span>
      <span class="kind">${c.family} · ${c.latency}c</span>`;
    const b = document.createElement("button");
    b.className = "ds-btn ds-btn-outline ds-btn-sm";
    b.type = "button";
    b.textContent = c.id === active ? "Loaded" : "Load";
    b.addEventListener("click", () => {
      $("chip").value = String(c.id);
      renderContainers();
      setStatus(`${c.name} loaded in the sandbox.`, "ok");
    });
    row.append(b);
    box.append(row);
  }
  $("container-count").textContent = `${CHIPS.length} models`;
}

function renderTape(sample) {
  const body = $("tape-body");
  body.innerHTML = "";
  if (!sample?.length) {
    body.innerHTML = `<tr><td colspan="5" class="empty">Run the feed to see messages.</td></tr>`;
    $("tape-count").textContent = "0 rows";
    return;
  }
  for (const r of sample.slice(0, 40)) {
    const tr = document.createElement("tr");
    const cls = r.isCorrupt ? "bad" : r.isTrade ? "trade" : "ref";
    const label = r.isCorrupt ? "ERR" : r.typeChar;
    tr.innerHTML = `<td><span class="tag ${cls}">${label}</span> ${r.isCorrupt ? "corrupt" : r.msgLen + "B"}</td>
      <td>${r.symbol || `loc:${r.locate}`}</td>
      <td class="num">${r.price ? usd(r.price) : "—"}</td>
      <td class="num">${r.shares ? fmt(r.shares) : "—"}</td>
      <td class="num">${r.latency}c</td>`;
    body.append(tr);
  }
  $("tape-count").textContent = `${fmt(sample.length)} rows`;
}

function renderMetrics(s) {
  $("m-gbps").textContent = s.gbps.toFixed(2);
  $("m-gbps-foot").textContent = `${s.chip === 5 ? "lossy" : "model"} · ${s.chipKey || ""}`;
  $("m-msgs").textContent = fmt(s.messages);
  $("m-mps").textContent = s.mps.toFixed(1);
  $("m-lat").textContent = `${chipById(s.chip).latency}c`;
  $("m-err").textContent = fmt(s.errors ?? 0);
  $("m-err").className = `metric-value ${s.errors ? "neg" : "pos"}`;
  $("m-err-foot").textContent = s.errors ? "mismatches" : "vs golden";
  $("k-corrupt").textContent = fmt(s.corrupt);
  $("k-bytes").textContent = `${(s.bytesIn / 1e6).toFixed(2)} MB`;
  $("k-frames").textContent = fmt(s.frames);
  $("k-wall").textContent = `${Math.round(s.wallMs)} ms`;
  $("lat-mode").textContent = `${chipById(s.chip).latency}c model`;
}

function fallbackBins(records, count) {
  const bins = new Uint32Array(128);
  let min = Infinity, max = 0;
  for (let i = 0; i < count; i++) {
    const p = records[i * 4 + 1];
    if (p && p < min) min = p;
    if (p > max) max = p;
  }
  if (!Number.isFinite(min)) min = 0;
  if (max <= min) max = min + 1;
  for (let i = 0; i < count; i++) {
    const p = records[i * 4 + 1];
    if (!p || p < min || p > max) continue;
    const b = Math.min(127, Math.floor(((p - min) * 128) / Math.max(1, max - min)));
    bins[b]++;
  }
  return bins;
}

function drawDepth(data) {
  if (!state.gpu) return;
  state.gpu.resize();
  const records = new Uint32Array(data.gpu);
  if (!state.gpu.ready) {
    state.gpu.bins = fallbackBins(records, data.gpuCount);
    try { state.gpu.draw2d(); } catch { /* keep the run result even if the canvas fails */ }
    // If a failed WebGPU init claimed the canvas, the first draw replaces it.
    // Repaint once on the next task so the fresh surface is guaranteed painted.
    setTimeout(() => { try { state.gpu.draw2d(); } catch { /* ignore */ } }, 60);
    return;
  }
  state.gpu.update(records, data.gpuCount).then(() => {
    if (state.gpu.ready) state.gpu.renderBins();
  }).catch((err) => {
    state.gpu.error = String(err?.stack || err);
    state.gpu.ready = false;
    state.gpu.kind = "cpu";
    state.gpu.resize();
    state.gpu.bins = fallbackBins(records, data.gpuCount);
    try { state.gpu.draw2d(); } catch { /* ignore */ }
    setTimeout(() => { try { state.gpu.draw2d(); } catch { /* ignore */ } }, 60);
    setBadge("gpu-badge", "GPU · CPU fallback");
    $("gpu-mode").textContent = "CPU";
  });
}

function renderRun(data) {
  state.lastRun = data;
  renderMetrics(data.summary);
  renderTape(data.sample);
  drawHistogram($("hist-canvas"), data.latencyHist);
  drawDepth(data);
  $("gpu-mode").textContent = state.gpu?.ready ? "WebGPU compute" : "Canvas2D";
  setStatus(`Run complete: ${fmt(data.summary.messages)} messages · ${data.summary.gbps.toFixed(2)} Gbps · ${fmt(data.summary.errors)} errors.`, data.summary.errors ? "error" : "ok");
  if (state.gpu?.ready) setBadge("gpu-badge", `GPU · ${state.gpu.adapterInfo?.description || "WebGPU"}`, "safe");
}

function renderCompare(rows) {
  const body = $("compare-body");
  body.innerHTML = "";
  for (const r of rows) {
    const tr = document.createElement("tr");
    const good = r.errors === 0;
    tr.innerHTML = `<td>${r.name}<br><span class="kind">${r.family}</span></td>
      <td class="num">${r.gbps.toFixed(2)}</td>
      <td class="num">${r.mps.toFixed(1)}</td>
      <td class="num">${(r.latencyNs ?? (r.latency || 0) * 3.1).toFixed(1)} ns</td>
      <td><span class="ds-badge ${good ? "ds-badge-safe" : "ds-badge-danger"}">${r.status}${good ? "" : " · " + fmt(r.errors)}</span></td>`;
    body.append(tr);
  }
}

function renderHistory(history) {
  const box = $("history-body");
  box.innerHTML = "";
  if (!history?.length) {
    box.innerHTML = `<p class="ds-supporting">No runs saved yet. Results stay in this browser (OPFS).</p>`;
    return;
  }
  for (const h of history) {
    const row = document.createElement("div");
    row.className = "history-row";
    const when = new Date(h.timestamp).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
    row.innerHTML = `<strong>${h.chipKey || chipById(h.chip).key}</strong>
      <span>${fmt(h.messages)}</span><span>${h.gbps.toFixed(2)} Gbps</span><span>${fmt(h.errors ?? 0)} err</span><span>${when}</span>`;
    const b = document.createElement("button");
    b.className = "ds-btn ds-btn-ghost ds-btn-sm";
    b.type = "button";
    b.textContent = "Restore";
    b.addEventListener("click", () => {
      renderMetrics(h);
      setStatus(`Restored summary from ${when}.`, "ok");
    });
    row.append(b);
    box.append(row);
  }
}

function run(extra = {}) {
  if (state.busy || !state.ready) return;
  state.busy = true;
  $("run").disabled = true;
  $("compare-btn").disabled = true;
  const count = Number($("count").value);
  const chip = Number($("chip").value);
  const seed = Math.max(0, Number($("seed").value) || 1337);
  const mode = Number($("mode").value);
  setStatus(`Generating ${fmt(count)} messages and running ${chipById(chip).name}…`);
  state.runSeq += 1;
  state.worker.postMessage({ type: "run", id: state.runSeq, chip, count, seed, mode, ...extra });
}

function compare() {
  if (state.busy || !state.ready) return;
  state.busy = true;
  $("run").disabled = true;
  $("compare-btn").disabled = true;
  setStatus("Comparing every chip against the golden parser…");
  state.worker.postMessage({ type: "compare", id: ++state.runSeq, count: Number($("count").value), seed: Number($("seed").value) || 1337 });
}

function toggleLive() {
  state.live = !state.live;
  $("live").setAttribute("aria-pressed", String(state.live));
  $("live").textContent = state.live ? "Stop" : "Live";
  if (state.live) {
    setStatus("Live mode: 5,000 messages every 900 ms. Not saved to history.");
    state.liveTimer = setInterval(() => {
      if (!state.busy) run({ count: 5000, save: false });
    }, 900);
  } else {
    clearInterval(state.liveTimer);
    state.liveTimer = null;
    setStatus("Live mode stopped.");
  }
}

async function init() {
  fillChips();
  state.gpu = new GpuLab($("gpu-canvas"));
  const gpuOk = await state.gpu.init();
  setBadge("gpu-badge", gpuOk ? `GPU · ${state.gpu.adapterInfo?.description || "WebGPU"}` : "GPU · CPU fallback", gpuOk ? "safe" : "outline");
  $("gpu-mode").textContent = gpuOk ? "WebGPU compute" : "Canvas2D";
  state.gpu.resize();

  state.worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  state.worker.onmessage = (ev) => {
    const m = ev.data;
    if (m.type === "ready") {
      state.ready = true;
      $("run").disabled = false;
      $("compare-btn").disabled = false;
      setBadge("wasm-badge", `WASM · v${(m.version >>> 16)}.${(m.version >>> 8) & 0xff} · ${(m.wasmBytes / 1024).toFixed(0)} KB`, "safe");
      setStatus("Ready. Everything runs locally.", "ok");
      state.worker.postMessage({ type: "history" });
      return;
    }
    if (m.type === "history") return renderHistory(m.history);
    if (m.type === "cleared") { renderHistory([]); setStatus("Local history cleared.", "ok"); return; }
    if (m.type === "error") {
      state.busy = false; $("run").disabled = false; $("compare-btn").disabled = false;
      setStatus(`Error: ${m.error.split("\n")[0]}`, "error");
      return;
    }
    if (m.type === "run") {
      state.busy = false; $("run").disabled = false; $("compare-btn").disabled = false;
      renderRun(m);
      renderHistory(m.history);
      return;
    }
    if (m.type === "compare") {
      state.busy = false; $("run").disabled = false; $("compare-btn").disabled = false;
      renderCompare(m.rows);
      setStatus(`Compared ${m.rows.length} chips in ${Math.round(m.wallMs)} ms.`, "ok");
    }
  };
  state.worker.onerror = (e) => {
    state.busy = false; $("run").disabled = false; $("compare-btn").disabled = false;
    setStatus(`Worker error: ${e.message}`, "error");
  };
  state.worker.postMessage({ type: "init", wasmUrl: new URL("./wasm/chiplab_core.wasm", import.meta.url).href });

  $("controls").addEventListener("submit", (e) => { e.preventDefault(); run(); });
  $("compare-btn").addEventListener("click", compare);
  $("live").addEventListener("click", toggleLive);
  $("clear").addEventListener("click", () => state.worker.postMessage({ type: "clear" }));
  $("chip").addEventListener("change", () => { renderContainers(); setStatus(`${chipById($("chip").value).name} selected.`); });
  $("mode").addEventListener("change", () => {
    if (Number($("mode").value) !== 0 && Number($("chip").value) !== 6) {
      $("chip").value = "6";
      renderContainers();
      setStatus("Mold/Ethernet streams use the MoldUDP64 front-end model.");
    }
  });
  window.addEventListener("keydown", (e) => {
    if (e.target.matches("input,select,textarea")) return;
    if (e.key === "r") run();
    if (e.key === "c") compare();
    if (e.key === "l") toggleLive();
  });
  window.addEventListener("resize", () => { state.gpu?.resize(); if (state.gpu?.ready) state.gpu.renderBins(); });
  window.addEventListener("online", () => setBadge("net-badge", "ONLINE"));
  window.addEventListener("offline", () => setBadge("net-badge", "LOCAL"));
  setBadge("net-badge", navigator.onLine ? "LOCAL" : "OFFLINE");

  if ("serviceWorker" in navigator) {
    let refreshed = false;
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (!refreshed) { refreshed = true; location.reload(); }
    });
    navigator.serviceWorker.register("./service-worker.js").then((r) => r.update()).catch(() => {});
  }
  navigator.storage?.persist?.().catch(() => {});
  window.__chiplab = state;
}

init().catch((e) => setStatus(`Init failed: ${e.message}`, "error"));
