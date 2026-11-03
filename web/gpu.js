// =============================================================================
// File: web/gpu.js
// Description: WebGPU compute (price bins + latency histogram) and WebGPU
//              render pass. Canvas2D fallback keeps the demo fully functional
//              on devices without WebGPU.
// =============================================================================
const COMPUTE_WGSL = /* wgsl */ `
struct Params { count: u32, minPrice: u32, maxPrice: u32, bins: u32 };
@group(0) @binding(0) var<storage, read> recs: array<u32>;
@group(0) @binding(1) var<storage, read_write> bins: array<atomic<u32>>;
@group(0) @binding(2) var<storage, read_write> hist: array<atomic<u32>>;
@group(0) @binding(3) var<uniform> p: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.count) { return; }
  let price = recs[i * 4u + 1u];
  if (price >= p.minPrice && price <= p.maxPrice) {
    let span = max(1u, p.maxPrice - p.minPrice);
    var b = ((price - p.minPrice) * p.bins) / span;
    if (b >= p.bins) { b = p.bins - 1u; }
    atomicAdd(&bins[b], 1u);
  }
  let lat = recs[i * 4u + 3u] & 0xFFFFu;
  atomicAdd(&hist[min(lat, 63u)], 1u);
}
`;

const RENDER_WGSL = /* wgsl */ `
struct VOut { @builtin(position) pos: vec4<f32>, @location(0) color: vec4<f32> };
@vertex fn vs(@location(0) p: vec2<f32>, @location(1) c: vec4<f32>) -> VOut {
  var o: VOut;
  o.pos = vec4<f32>(p, 0.0, 1.0);
  o.color = c;
  return o;
}
@fragment fn fs(i: VOut) -> @location(0) vec4<f32> { return i.color; }
`;

export class GpuLab {
  constructor(canvas) {
    this.canvas = canvas;
    this.ready = false;
    this.kind = "cpu";
    this.bins = new Uint32Array(128);
    this.hist = new Uint32Array(64);
    this._capacity = 0;
    this._vbo = null;
    this._vboSize = 0;
    // Do not call getContext("2d") here: it would claim the canvas and make
    // getContext("webgpu") return null. The fallback context is created lazily.
  }

  async init() {
    if (!navigator.gpu) return false;
    try {
      const adapter = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
      if (!adapter) return false;
      const device = await adapter.requestDevice();
      this.device = device;
      this.adapterInfo = adapter.info || {};
      this.format = navigator.gpu.getPreferredCanvasFormat();
      // Build pipelines before claiming the canvas context. If anything fails
      // here, the canvas is still free for the Canvas2D fallback.
      this._createPipelines();
      const ctx = this.canvas.getContext("webgpu");
      if (!ctx) return false;
      ctx.configure({ device, format: this.format, alphaMode: "opaque" });
      this.ctx = ctx;
      this.ready = true;
      this.kind = "webgpu";
      this.resize();
      device.lost.then(() => { this.ready = false; this.kind = "cpu"; });
      return true;
    } catch (err) {
      this.ready = false;
      this.kind = "cpu";
      this.error = String(err?.stack || err);
      return false;
    }
  }

  _createPipelines() {
    const device = this.device;
    this.compute = device.createComputePipeline({
      layout: "auto",
      compute: { module: device.createShaderModule({ code: COMPUTE_WGSL }), entryPoint: "main" },
    });
    this.render = device.createRenderPipeline({
      layout: "auto",
      vertex: {
        module: device.createShaderModule({ code: RENDER_WGSL }),
        entryPoint: "vs",
        buffers: [{
          arrayStride: 24,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x2" },
            { shaderLocation: 1, offset: 8, format: "float32x4" },
          ],
        }],
      },
      fragment: {
        module: device.createShaderModule({ code: RENDER_WGSL }),
        entryPoint: "fs",
        targets: [{ format: this.format }],
      },
      primitive: { topology: "triangle-list" },
    });
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(320, this.canvas.clientWidth | 0);
    const h = Math.max(160, this.canvas.clientHeight | 0);
    this.canvas.width = Math.floor(w * dpr);
    this.canvas.height = Math.floor(h * dpr);
  }

  async update(records, count) {
    if (!this.ready) return { bins: this.bins, hist: this.hist };
    const device = this.device;
    const binsN = 128, histN = 64;
    if (!this._buf || this._capacity < count) {
      this._capacity = Math.max(count, 1024);
      this._buf?.destroy?.();
      this._buf = device.createBuffer({ size: this._capacity * 16, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
      this._bins = device.createBuffer({ size: binsN * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
      this._hist = device.createBuffer({ size: histN * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
      this._params = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      this._staging = device.createBuffer({ size: (binsN + histN) * 4, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
      this._bind = device.createBindGroup({
        layout: this.compute.getBindGroupLayout(0),
        entries: [
          { binding: 0, resource: { buffer: this._buf } },
          { binding: 1, resource: { buffer: this._bins } },
          { binding: 2, resource: { buffer: this._hist } },
          { binding: 3, resource: { buffer: this._params } },
        ],
      });
    }
    device.queue.writeBuffer(this._buf, 0, records);
    device.queue.writeBuffer(this._bins, 0, new Uint32Array(binsN));
    device.queue.writeBuffer(this._hist, 0, new Uint32Array(histN));
    // Price range from the records (CPU scan is 1 pass, still local).
    let min = 0xffffffff, max = 0;
    for (let i = 0; i < count; i++) {
      const p = records[i * 4 + 1];
      if (p && p < min) min = p;
      if (p > max) max = p;
    }
    if (min === 0xffffffff) min = 0;
    if (max <= min) max = min + 1;
    device.queue.writeBuffer(this._params, 0, new Uint32Array([count, min, max, binsN]));
    const enc = device.createCommandEncoder();
    const pass = enc.beginComputePass();
    pass.setPipeline(this.compute);
    pass.setBindGroup(0, this._bind);
    pass.dispatchWorkgroups(Math.ceil(count / 64));
    pass.end();
    enc.copyBufferToBuffer(this._bins, 0, this._staging, 0, binsN * 4);
    enc.copyBufferToBuffer(this._hist, 0, this._staging, binsN * 4, histN * 4);
    device.queue.submit([enc.finish()]);
    await this._staging.mapAsync(GPUMapMode.READ);
    const copy = new Uint32Array(this._staging.getMappedRange().slice(0));
    this._staging.unmap();
    this.bins = copy.slice(0, binsN);
    this.hist = copy.slice(binsN, binsN + histN);
    return { bins: this.bins, hist: this.hist, range: [min, max] };
  }

  _bars(bins) {
    const values = Array.from(bins);
    let max = 0;
    for (const v of values) if (v > max) max = v;
    if (!max) max = 1;
    const data = new Float32Array(128 * 6 * 6);
    let p = 0;
    for (let i = 0; i < 128; i++) {
      const w = 1.9 / 128;
      const x0 = -0.95 + i * w + w * 0.12;
      const x1 = x0 + w * 0.76;
      const h = (values[i] / max) * 1.7;
      const y0 = -0.9;
      const y1 = -0.9 + h;
      const t = values[i] / max;
      const color = [0.30 + 0.45 * t, 0.80 + 0.15 * t, 0.38 + 0.08 * t, 1];
      const quad = [
        x0, y0, ...color, x1, y0, ...color, x1, y1, ...color,
        x0, y0, ...color, x1, y1, ...color, x0, y1, ...color,
      ];
      data.set(quad, p); p += quad.length;
    }
    return data;
  }

  renderBins() {
    if (!this.ready) { this.draw2d(); return; }
    const device = this.device;
    const verts = this._bars(this.bins);
    if (!this._vbo || this._vboSize < verts.byteLength) {
      this._vbo?.destroy?.();
      this._vboSize = Math.max(verts.byteLength, 128 * 6 * 6 * 4);
      this._vbo = device.createBuffer({ size: this._vboSize, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
    }
    device.queue.writeBuffer(this._vbo, 0, verts);
    const enc = device.createCommandEncoder();
    const pass = enc.beginRenderPass({
      colorAttachments: [{
        view: this.ctx.getCurrentTexture().createView(),
        clearValue: { r: 0.055, g: 0.065, b: 0.06, a: 1 },
        loadOp: "clear", storeOp: "store",
      }],
    });
    pass.setPipeline(this.render);
    pass.setVertexBuffer(0, this._vbo);
    pass.draw(128 * 6);
    pass.end();
    device.queue.submit([enc.finish()]);
  }

  draw2d() {
    let c = this.canvas;
    let ctx = c.getContext("2d");
    if (!ctx) {
      // The canvas was already claimed by a failed WebGPU init. Replace it with
      // a fresh element so the fallback is always available.
      const clone = c.cloneNode(false);
      c.replaceWith(clone);
      this.canvas = clone;
      c = clone;
      this.resize();
      ctx = c.getContext("2d");
      if (!ctx) return;
    }
    const w = c.width, h = c.height;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = "#0e100f";
    ctx.fillRect(0, 0, w, h);
    const max = Math.max(1, ...this.bins);
    const bw = w / this.bins.length;
    for (let i = 0; i < this.bins.length; i++) {
      const bh = (this.bins[i] / max) * (h - 24);
      const t = this.bins[i] / max;
      ctx.fillStyle = `rgba(${Math.round(80 + 100 * t)},${Math.round(220 - 20 * t)},${Math.round(110 + 20 * t)},0.9)`;
      ctx.fillRect(i * bw + 1, h - bh, Math.max(1, bw - 2), bh);
    }
  }
}

export function drawHistogram(canvas, hist) {
  const c = canvas;
  const ctx = c.getContext("2d");
  if (!ctx) return;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  c.width = Math.floor(c.clientWidth * dpr);
  c.height = Math.floor(c.clientHeight * dpr);
  const w = c.width, h = c.height;
  ctx.clearRect(0, 0, w, h);
  const max = Math.max(1, ...hist);
  const bw = w / hist.length;
  for (let i = 0; i < hist.length; i++) {
    const bh = (hist[i] / max) * (h - 18);
    const t = i / hist.length;
    ctx.fillStyle = `rgba(${Math.round(230 - 60 * t)},${Math.round(190 - 40 * t)},${Math.round(70 + 40 * t)},0.9)`;
    ctx.fillRect(i * bw + 1, h - bh, Math.max(1, bw - 2), bh);
  }
  ctx.strokeStyle = "rgba(255,255,255,0.10)";
  ctx.lineWidth = 1;
  for (let y = 1; y < 4; y++) {
    ctx.beginPath(); ctx.moveTo(0, (h * y) / 4); ctx.lineTo(w, (h * y) / 4); ctx.stroke();
  }
}
