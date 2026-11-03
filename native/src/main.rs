// =============================================================================
// File: native/src/main.rs
// Description: Native Vulkan/DX12 compute runner via wgpu.
//   - enumerates adapters (probe)
//   - bins ITCH price/latency records on the GPU
//   - optional Windows process boost (priority + affinity), opt-in only
//
// Build: cargo build --manifest-path native/Cargo.toml --release
// Run:   chiplab-native --input reports/native_records.bin --boost
// =============================================================================
use std::fs;
use std::time::Instant;

const BINS: usize = 128;
const HIST: usize = 64;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct Params {
    count: u32,
    min_price: u32,
    max_price: u32,
    bins: u32,
}

const WGSL: &str = r#"
struct Params { count: u32, min_price: u32, max_price: u32, bins: u32 };
@group(0) @binding(0) var<storage, read> recs: array<u32>;
@group(0) @binding(1) var<storage, read_write> bins: array<atomic<u32>>;
@group(0) @binding(2) var<storage, read_write> hist: array<atomic<u32>>;
@group(0) @binding(3) var<uniform> p: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.count) { return; }
  let price = recs[i * 4u + 1u];
  if (price >= p.min_price && price <= p.max_price) {
    let span = max(1u, p.max_price - p.min_price);
    var b = ((price - p.min_price) * p.bins) / span;
    if (b >= p.bins) { b = p.bins - 1u; }
    atomicAdd(&bins[b], 1u);
  }
  let lat = recs[i * 4u + 3u] & 0xFFFFu;
  atomicAdd(&hist[min(lat, 63u)], 1u);
}
"#;

fn arg(name: &str, dflt: &str) -> String {
    let a: Vec<String> = std::env::args().collect();
    a.iter().position(|x| x == name)
        .and_then(|i| a.get(i + 1).cloned())
        .unwrap_or_else(|| dflt.to_string())
}
fn has(name: &str) -> bool { std::env::args().any(|x| x == name) }

#[cfg(windows)]
mod boost {
    #[link(name = "kernel32")]
    extern "system" {
        fn GetCurrentProcess() -> isize;
        fn SetPriorityClass(h: isize, c: u32) -> i32;
        fn SetProcessAffinityMask(h: isize, m: usize) -> i32;
    }
    pub fn apply(priority: bool, affinity: bool) {
        const HIGH_PRIORITY_CLASS: u32 = 0x0000_0080;
        unsafe {
            let h = GetCurrentProcess();
            if priority {
                let ok = SetPriorityClass(h, HIGH_PRIORITY_CLASS);
                println!("[boost] priority -> HIGH_PRIORITY_CLASS: {}", if ok != 0 { "ok" } else { "failed" });
            }
            if affinity {
                let ok = SetProcessAffinityMask(h, 0xFF); // first 8 logical CPUs
                println!("[boost] affinity -> 0xFF: {}", if ok != 0 { "ok" } else { "failed" });
            }
        }
    }
}
#[cfg(not(windows))]
mod boost {
    pub fn apply(_priority: bool, _affinity: bool) {
        println!("[boost] not available on this platform");
    }
}

fn main() {
    let input = arg("--input", "reports/native_records.bin");
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::default());

    if has("--probe") {
        println!("wgpu adapters:");
        for a in instance.enumerate_adapters(wgpu::Backends::all()) {
            let i = a.get_info();
            println!("  {} | backend={:?} | type={:?} | vendor=0x{:04x} device=0x{:04x}",
                     i.name, i.backend, i.device_type, i.vendor, i.device);
        }
        return;
    }

    let data = match fs::read(&input) {
        Ok(d) => d,
        Err(e) => { eprintln!("cannot read {input}: {e}\nrun: node scripts/export_records.mjs"); std::process::exit(2); }
    };
    if data.len() % 16 != 0 || data.is_empty() {
        eprintln!("record file must be a non-empty multiple of 16 bytes");
        std::process::exit(2);
    }
    let count = (data.len() / 16) as u32;
    let records: &[u32] = bytemuck::cast_slice(&data);
    let mut min = u32::MAX;
    let mut max = 0u32;
    for i in 0..count as usize {
        let p = records[i * 4 + 1];
        if p != 0 && p < min { min = p; }
        if p > max { max = p; }
    }
    if min == u32::MAX { min = 0; }
    if max <= min { max = min + 1; }

    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    })).expect("no GPU adapter");
    let info = adapter.get_info();
    println!("adapter: {} | backend={:?} | type={:?}", info.name, info.backend, info.device_type);

    let (device, queue) = pollster::block_on(adapter.request_device(
        &wgpu::DeviceDescriptor { label: Some("chiplab"), ..Default::default() }, None,
    )).expect("device");

    let auto_boost = has("--auto-boost") && !matches!(info.device_type, wgpu::DeviceType::Cpu);
    if has("--boost") || auto_boost {
        if auto_boost { println!("[boost] auto-boost: GPU adapter present"); }
        boost::apply(true, has("--affinity"));
    }

    let rec_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("records"), size: data.len() as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
    });
    queue.write_buffer(&rec_buf, 0, &data);
    let bins_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("bins"), size: (BINS * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let hist_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("hist"), size: (HIST * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let params_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("params"), size: 16,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
    });
    queue.write_buffer(&bins_buf, 0, bytemuck::cast_slice(&[0u32; BINS]));
    queue.write_buffer(&hist_buf, 0, bytemuck::cast_slice(&[0u32; HIST]));
    queue.write_buffer(&params_buf, 0, bytemuck::bytes_of(&Params { count, min_price: min, max_price: max, bins: BINS as u32 }));

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("bin"), source: wgpu::ShaderSource::Wgsl(WGSL.into()) });
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("layout"),
        entries: &[
            wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: false }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: false }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None },
        ],
    });
    let bind = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("bind"), layout: &layout,
        entries: &[
            wgpu::BindGroupEntry { binding: 0, resource: rec_buf.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 1, resource: bins_buf.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 2, resource: hist_buf.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 3, resource: params_buf.as_entire_binding() },
        ],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("pl"), bind_group_layouts: &[&layout], push_constant_ranges: &[] });
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("bin"), layout: Some(&pipeline_layout), module: &shader, entry_point: "main",
    });
    let staging = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("staging"), size: ((BINS + HIST) * 4) as u64,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
    });

    let t0 = Instant::now();
    let mut enc = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("enc") });
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("pass"), timestamp_writes: None });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind, &[]);
        pass.dispatch_workgroups((count + 63) / 64, 1, 1);
    }
    enc.copy_buffer_to_buffer(&bins_buf, 0, &staging, 0, (BINS * 4) as u64);
    enc.copy_buffer_to_buffer(&hist_buf, 0, &staging, (BINS * 4) as u64, (HIST * 4) as u64);
    queue.submit(Some(enc.finish()));
    let slice = staging.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    device.poll(wgpu::Maintain::Wait);
    let out = slice.get_mapped_range();
    let values: &[u32] = bytemuck::cast_slice(&out);
    let bins = &values[..BINS];
    let hist = &values[BINS..BINS + HIST];
    let elapsed = t0.elapsed();
    let checksum: u64 = bins.iter().chain(hist.iter()).map(|&x| x as u64).sum();
    println!("records: {count} | price range: {min}..{max} | time: {:.2} ms", elapsed.as_secs_f64() * 1000.0);
    println!("bins: {:?}", &bins[..8]);
    println!("hist: {:?}", &hist[..8]);
    println!("checksum: {checksum}");

    let mut blob = Vec::with_capacity((BINS + HIST) * 4);
    blob.extend_from_slice(bytemuck::cast_slice(bins));
    blob.extend_from_slice(bytemuck::cast_slice(hist));
    fs::write("reports/native_bins.bin", &blob).ok();
    drop(out);
    staging.unmap();
}
