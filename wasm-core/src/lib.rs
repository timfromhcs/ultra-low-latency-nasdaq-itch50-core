// =============================================================================
// File: wasm-core/src/lib.rs
// Description: Portable ITCH 5.0 / MoldUDP64 chip-lab core.
//
// The same WebAssembly artifact runs in the browser (WebGPU demo) and in the
// Node local backend. It contains:
//   * an independent field-accurate ITCH parser (Rust, no deps)
//   * deterministic ITCH / MoldUDP64 / Ethernet frame generators
//   * several "chip" models for honest head-to-head comparison
//   * a top-of-book builder used by the WebGPU visualisation
//
// Record format (80 bytes, little endian) is identical to tb/itch_model.py.
// =============================================================================

const RECORD_SIZE: usize = 80;
const HEADER_SIZE: usize = 48;
const MAGIC: u32 = 0x4241_4C43; // "CLAB"

const MSG_SYSTEM_EVENT: u8 = 0x53;
const MSG_STOCK_DIRECTORY: u8 = 0x52;
const MSG_STOCK_TRADING_ACTION: u8 = 0x48;
const MSG_REG_SHO_RESTRICTION: u8 = 0x59;
const MSG_MARKET_PARTICIPANT_POS: u8 = 0x4C;
const MSG_MWCB_DECLINE_LEVEL: u8 = 0x56;
const MSG_MWCB_STATUS: u8 = 0x57;
const MSG_QUOTING_PERIOD_UPDATE: u8 = 0x4B;
const MSG_LULD_AUCTION_COLLAR: u8 = 0x4A;
const MSG_OPERATIONAL_HALT: u8 = 0x68;
const MSG_ADD_ORDER: u8 = 0x41;
const MSG_ADD_ORDER_MPID: u8 = 0x46;
const MSG_ORDER_EXECUTED: u8 = 0x45;
const MSG_ORDER_EXECUTED_PRICE: u8 = 0x43;
const MSG_ORDER_CANCEL: u8 = 0x58;
const MSG_ORDER_DELETE: u8 = 0x44;
const MSG_ORDER_REPLACE: u8 = 0x55;
const MSG_TRADE_NON_CROSS: u8 = 0x50;
const MSG_CROSS_TRADE: u8 = 0x51;
const MSG_BROKEN_TRADE: u8 = 0x42;
const MSG_NOII: u8 = 0x49;
const MSG_RPII: u8 = 0x4E;

fn msg_len(t: u8) -> usize {
    match t {
        MSG_SYSTEM_EVENT => 12,
        MSG_STOCK_DIRECTORY => 39,
        MSG_STOCK_TRADING_ACTION => 25,
        MSG_REG_SHO_RESTRICTION => 20,
        MSG_MARKET_PARTICIPANT_POS => 26,
        MSG_MWCB_DECLINE_LEVEL => 35,
        MSG_MWCB_STATUS => 12,
        MSG_QUOTING_PERIOD_UPDATE => 28,
        MSG_LULD_AUCTION_COLLAR => 35,
        MSG_OPERATIONAL_HALT => 21,
        MSG_ADD_ORDER => 36,
        MSG_ADD_ORDER_MPID => 40,
        MSG_ORDER_EXECUTED => 31,
        MSG_ORDER_EXECUTED_PRICE => 36,
        MSG_ORDER_CANCEL => 23,
        MSG_ORDER_DELETE => 19,
        MSG_ORDER_REPLACE => 35,
        MSG_TRADE_NON_CROSS => 44,
        MSG_CROSS_TRADE => 40,
        MSG_BROKEN_TRADE => 19,
        MSG_NOII => 50,
        MSG_RPII => 20,
        _ => 0,
    }
}

fn is_trade(t: u8) -> bool {
    matches!(t, MSG_ADD_ORDER | MSG_ADD_ORDER_MPID | MSG_ORDER_EXECUTED
        | MSG_ORDER_EXECUTED_PRICE | MSG_ORDER_CANCEL | MSG_ORDER_DELETE
        | MSG_ORDER_REPLACE | MSG_TRADE_NON_CROSS | MSG_CROSS_TRADE)
}

fn be(d: &[u8], off: usize, n: usize) -> u64 {
    let mut v = 0u64;
    for i in 0..n {
        v = (v << 8) | *d.get(off + i).unwrap_or(&0) as u64;
    }
    v
}

fn fnv1a(data: &[u8]) -> u32 {
    let mut h = 0x811C_9DC5u32;
    for &b in data {
        h ^= b as u32;
        h = h.wrapping_mul(0x0100_0193);
    }
    h
}

#[derive(Clone, Copy, Default)]
struct Msg {
    t: u8,
    flags: u8,
    len: u8,
    locate: u16,
    tracking: u16,
    ts: u64,
    order_ref: u64,
    new_ref: u64,
    shares: u64,
    price: u32,
    side: u8,
    printable: u8,
    event: u8,
    match_num: u64,
    stock: u64,
    mpid: u32,
    ref_value: u32,
    checksum: u32,
    latency: u16,
}

impl Msg {
    fn write(&self, out: &mut [u8]) {
        for b in out[..RECORD_SIZE].iter_mut() { *b = 0; }
        out[0] = self.t;
        out[1] = self.flags;
        out[2] = self.len;
        out[4..6].copy_from_slice(&self.locate.to_le_bytes());
        out[6..8].copy_from_slice(&self.tracking.to_le_bytes());
        out[8..16].copy_from_slice(&self.ts.to_le_bytes());
        out[16..24].copy_from_slice(&self.order_ref.to_le_bytes());
        out[24..32].copy_from_slice(&self.new_ref.to_le_bytes());
        out[32..40].copy_from_slice(&self.shares.to_le_bytes());
        out[40..44].copy_from_slice(&self.price.to_le_bytes());
        out[44] = self.side;
        out[45] = self.printable;
        out[46] = self.event;
        out[48..56].copy_from_slice(&self.match_num.to_le_bytes());
        out[56..64].copy_from_slice(&self.stock.to_le_bytes());
        out[64..68].copy_from_slice(&self.mpid.to_le_bytes());
        out[68..72].copy_from_slice(&self.ref_value.to_le_bytes());
        out[72..76].copy_from_slice(&self.checksum.to_le_bytes());
        out[76..78].copy_from_slice(&self.latency.to_le_bytes());
    }
}

fn parse_one(d: &[u8], off: usize) -> Option<(Msg, usize)> {
    if off >= d.len() { return None; }
    let t = d[off];
    let len = msg_len(t);
    if len == 0 {
        return Some((Msg { t, flags: 0x04, ..Default::default() }, 1));
    }
    if off + len > d.len() { return None; }
    let m = &d[off..off + len];
    let mut r = Msg {
        t,
        flags: if is_trade(t) { 0x01 } else { 0x02 },
        len: len as u8,
        locate: be(m, 1, 2) as u16,
        tracking: be(m, 3, 2) as u16,
        ts: be(m, 5, 6),
        checksum: fnv1a(m),
        ..Default::default()
    };
    match t {
        MSG_ADD_ORDER => {
            r.order_ref = be(m, 11, 8); r.side = m[19]; r.shares = be(m, 20, 4);
            r.stock = be(m, 24, 8); r.price = be(m, 32, 4) as u32;
        }
        MSG_ADD_ORDER_MPID => {
            r.order_ref = be(m, 11, 8); r.side = m[19]; r.shares = be(m, 20, 4);
            r.stock = be(m, 24, 8); r.price = be(m, 32, 4) as u32;
            r.mpid = be(m, 36, 4) as u32;
        }
        MSG_ORDER_EXECUTED => {
            r.order_ref = be(m, 11, 8); r.shares = be(m, 19, 4); r.match_num = be(m, 23, 8);
        }
        MSG_ORDER_EXECUTED_PRICE => {
            r.order_ref = be(m, 11, 8); r.shares = be(m, 19, 4);
            r.printable = if m[23] == b'Y' { 1 } else { 0 };
            r.match_num = be(m, 24, 8); r.price = be(m, 32, 4) as u32;
        }
        MSG_ORDER_CANCEL => { r.order_ref = be(m, 11, 8); r.shares = be(m, 19, 4); }
        MSG_ORDER_DELETE => { r.order_ref = be(m, 11, 8); }
        MSG_ORDER_REPLACE => {
            r.order_ref = be(m, 11, 8); r.new_ref = be(m, 19, 8);
            r.shares = be(m, 27, 4); r.price = be(m, 31, 4) as u32;
        }
        MSG_TRADE_NON_CROSS => {
            r.order_ref = be(m, 11, 8); r.side = m[19]; r.shares = be(m, 20, 4);
            r.stock = be(m, 24, 8); r.price = be(m, 32, 4) as u32; r.match_num = be(m, 36, 8);
        }
        MSG_CROSS_TRADE => {
            r.shares = be(m, 11, 8); r.stock = be(m, 19, 8);
            r.price = be(m, 27, 4) as u32; r.match_num = be(m, 31, 8); r.event = m[39];
        }
        MSG_SYSTEM_EVENT => { r.event = m[11]; }
        MSG_STOCK_DIRECTORY => {
            r.stock = be(m, 11, 8); r.event = m[19]; r.ref_value = be(m, 21, 4) as u32;
        }
        MSG_STOCK_TRADING_ACTION => {
            r.stock = be(m, 11, 8); r.event = m[19]; r.ref_value = be(m, 21, 4) as u32;
        }
        MSG_REG_SHO_RESTRICTION => { r.stock = be(m, 11, 8); r.event = m[19]; }
        MSG_MARKET_PARTICIPANT_POS => {
            r.mpid = be(m, 11, 4) as u32; r.stock = be(m, 15, 8); r.event = m[25];
        }
        MSG_OPERATIONAL_HALT => { r.stock = be(m, 11, 8); r.event = m[20]; }
        MSG_MWCB_DECLINE_LEVEL => { r.ref_value = be(m, 11, 4) as u32; }
        MSG_MWCB_STATUS => { r.event = m[11]; }
        MSG_QUOTING_PERIOD_UPDATE => { r.stock = be(m, 11, 8); r.event = m[19]; }
        MSG_LULD_AUCTION_COLLAR => { r.stock = be(m, 11, 8); }
        MSG_BROKEN_TRADE => { r.match_num = be(m, 11, 8); }
        MSG_NOII => { r.stock = be(m, 11, 8); }
        MSG_RPII => { r.stock = be(m, 11, 8); r.side = m[19]; }
        _ => {}
    }
    Some((r, len))
}

#[derive(Default)]
struct Stats {
    count: u64,
    corrupt: u64,
    consumed: u64,
    cycles: u64,
}

fn parse_itch(d: &[u8], emit_reference: bool, latency: u16, out: &mut Vec<u8>, st: &mut Stats) {
    let mut off = 0usize;
    let mut rec = [0u8; RECORD_SIZE];
    while off < d.len() {
        match parse_one(d, off) {
            Some((mut m, used)) => {
                if m.flags & 0x04 != 0 { st.corrupt += 1; }
                if emit_reference || m.flags & 0x02 == 0 {
                    m.latency = latency;
                    m.write(&mut rec);
                    out.extend_from_slice(&rec);
                    st.count += 1;
                }
                off += used;
            }
            None => break,
        }
    }
    st.consumed = off as u64;
    st.cycles = ((d.len() as u64 + 15) / 16).max(st.count) + latency as u64;
}

// -----------------------------------------------------------------------------
// Deterministic generator
// -----------------------------------------------------------------------------
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn r(&mut self, n: u64) -> u64 { if n == 0 { 0 } else { self.next() % n } }
}

const SYMBOLS: [&[u8; 8]; 10] = [
    b"AAPL    ", b"MSFT    ", b"NVDA    ", b"GOOGL   ", b"AMZN    ",
    b"TSLA    ", b"META    ", b"SPY     ", b"QQQ     ", b"IWM     ",
];
const MPIDS: [&[u8; 4]; 5] = [b"NSDQ", b"ARCA", b"BATS", b"EDGX", b"XNYS"];
const TYPES: [u8; 22] = [
    MSG_ADD_ORDER, MSG_ADD_ORDER_MPID, MSG_ORDER_EXECUTED, MSG_ORDER_EXECUTED_PRICE,
    MSG_ORDER_CANCEL, MSG_ORDER_DELETE, MSG_ORDER_REPLACE, MSG_TRADE_NON_CROSS,
    MSG_CROSS_TRADE, MSG_SYSTEM_EVENT, MSG_STOCK_DIRECTORY, MSG_STOCK_TRADING_ACTION,
    MSG_REG_SHO_RESTRICTION, MSG_MARKET_PARTICIPANT_POS, MSG_MWCB_DECLINE_LEVEL,
    MSG_MWCB_STATUS, MSG_QUOTING_PERIOD_UPDATE, MSG_LULD_AUCTION_COLLAR,
    MSG_OPERATIONAL_HALT, MSG_BROKEN_TRADE, MSG_NOII, MSG_RPII,
];

fn put(d: &mut [u8], off: usize, v: u64, n: usize) {
    for i in 0..n {
        d[off + i] = ((v >> ((n - 1 - i) * 8)) & 0xFF) as u8;
    }
}

fn build_message(rng: &mut Rng, t: u8, idx: u64) -> Vec<u8> {
    let len = msg_len(t);
    let mut d = vec![0u8; len];
    d[0] = t;
    put(&mut d, 1, 1 + rng.r(7999), 2);
    put(&mut d, 3, idx & 0xFFFF, 2);
    put(&mut d, 5, 34_200_000_000_000 + idx, 6);
    let locate = be(&d, 1, 2) as usize;
    let _ = locate;
    let stock = SYMBOLS[rng.r(SYMBOLS.len() as u64) as usize];
    let mpid = MPIDS[rng.r(MPIDS.len() as u64) as usize];
    let refn = 1_000_000 + idx;
    let shares = 1 + rng.r(2_000_000);
    let price = 1 + rng.r(5_000_000);
    let matchn = rng.next();
    let side = if rng.next() & 1 == 0 { b'B' } else { b'S' };
    match t {
        MSG_ADD_ORDER => {
            put(&mut d, 11, refn, 8); d[19] = side; put(&mut d, 20, shares, 4);
            d[24..32].copy_from_slice(stock); put(&mut d, 32, price, 4);
        }
        MSG_ADD_ORDER_MPID => {
            put(&mut d, 11, refn, 8); d[19] = side; put(&mut d, 20, shares, 4);
            d[24..32].copy_from_slice(stock); put(&mut d, 32, price, 4);
            d[36..40].copy_from_slice(mpid);
        }
        MSG_ORDER_EXECUTED => {
            put(&mut d, 11, refn, 8); put(&mut d, 19, shares, 4); put(&mut d, 23, matchn, 8);
        }
        MSG_ORDER_EXECUTED_PRICE => {
            put(&mut d, 11, refn, 8); put(&mut d, 19, shares, 4);
            d[23] = if rng.next() & 1 == 0 { b'Y' } else { b'N' };
            put(&mut d, 24, matchn, 8); put(&mut d, 32, price, 4);
        }
        MSG_ORDER_CANCEL => { put(&mut d, 11, refn, 8); put(&mut d, 19, shares, 4); }
        MSG_ORDER_DELETE => { put(&mut d, 11, refn, 8); }
        MSG_ORDER_REPLACE => {
            put(&mut d, 11, refn, 8); put(&mut d, 19, refn + 1, 8);
            put(&mut d, 27, shares, 4); put(&mut d, 31, price, 4);
        }
        MSG_TRADE_NON_CROSS => {
            put(&mut d, 11, refn, 8); d[19] = side; put(&mut d, 20, shares, 4);
            d[24..32].copy_from_slice(stock); put(&mut d, 32, price, 4); put(&mut d, 36, matchn, 8);
        }
        MSG_CROSS_TRADE => {
            put(&mut d, 11, rng.next() & 0x0000_FFFF_FFFF_FFFF, 8);
            d[19..27].copy_from_slice(stock); put(&mut d, 27, price, 4);
            put(&mut d, 31, matchn, 8); d[39] = if rng.next() & 1 == 0 { b'O' } else { b'A' };
        }
        MSG_SYSTEM_EVENT => { d[11] = b"OQSC"[(rng.r(4)) as usize]; }
        MSG_STOCK_DIRECTORY => {
            d[11..19].copy_from_slice(stock); d[19] = b"QGNSPZ"[rng.r(6) as usize];
            d[20] = b"CNGD"[rng.r(4) as usize];
            put(&mut d, 21, if rng.next() & 1 == 0 { 100 } else { 1 }, 4);
            d[25] = b"NY"[rng.r(2) as usize];
            d[26] = b"QGNSPZ"[rng.r(6) as usize];
            d[27] = b"0123"[rng.r(4) as usize];
            d[28] = b"PNY"[rng.r(3) as usize];
            d[29] = b"NY"[rng.r(2) as usize];
            d[30] = (rng.next() & 1) as u8;
            d[31] = 1 + rng.r(3) as u8;
            d[32] = (rng.next() & 1) as u8;
            put(&mut d, 33, 1 + rng.r(100), 4);
            d[37] = (rng.next() & 1) as u8;
            d[38] = 1 + rng.r(5) as u8;
        }
        MSG_STOCK_TRADING_ACTION => {
            d[11..19].copy_from_slice(stock); d[19] = b"THB"[rng.r(3) as usize];
            d[20] = 0; put(&mut d, 21, rng.next() & 0xFFFF_FFFF, 4);
        }
        MSG_REG_SHO_RESTRICTION => {
            d[11..19].copy_from_slice(stock); d[19] = b"01"[rng.r(2) as usize];
        }
        MSG_MARKET_PARTICIPANT_POS => {
            d[11..15].copy_from_slice(mpid); d[15..23].copy_from_slice(stock);
            d[23] = (rng.next() & 1) as u8; d[24] = b"012"[rng.r(3) as usize];
            d[25] = b"APDN"[rng.r(4) as usize];
        }
        MSG_MWCB_DECLINE_LEVEL => { put(&mut d, 11, rng.next(), 8); }
        MSG_MWCB_STATUS => { d[11] = 1 + rng.r(3) as u8; }
        MSG_QUOTING_PERIOD_UPDATE => {
            d[11..19].copy_from_slice(stock); d[19] = b"BE"[rng.r(2) as usize];
            put(&mut d, 20, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 24, rng.next() & 0xFFFF_FFFF, 4);
        }
        MSG_LULD_AUCTION_COLLAR => {
            d[11..19].copy_from_slice(stock);
            put(&mut d, 19, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 23, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 27, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 31, rng.next() & 0xFFFF_FFFF, 4);
        }
        MSG_OPERATIONAL_HALT => {
            d[11..19].copy_from_slice(stock); d[19] = b"QGNSPZ"[rng.r(6) as usize];
            d[20] = b"012"[rng.r(3) as usize];
        }
        MSG_BROKEN_TRADE => { put(&mut d, 11, matchn, 8); }
        MSG_NOII => {
            d[11..19].copy_from_slice(stock);
            put(&mut d, 19, rng.next(), 8); put(&mut d, 27, rng.next(), 8);
            d[35] = b"BSN"[rng.r(3) as usize];
            put(&mut d, 36, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 40, rng.next() & 0xFFFF_FFFF, 4);
            put(&mut d, 44, rng.next() & 0xFFFF_FFFF, 4);
            d[48] = b"OC"[rng.r(2) as usize]; d[49] = rng.r(4) as u8;
        }
        MSG_RPII => { d[11..19].copy_from_slice(stock); d[19] = b"YN"[rng.r(2) as usize]; }
        _ => {}
    }
    d
}

fn write_mold_header(out: &mut Vec<u8>, seq: u64, count: u16) {
    out.extend_from_slice(b"SESSION001"); // 10-byte session
    out.extend_from_slice(&seq.to_be_bytes());
    out.extend_from_slice(&count.to_be_bytes());
}

fn write_eth_ip_udp(out: &mut Vec<u8>, payload_len: usize) {
    out.extend_from_slice(&[0x01, 0x00, 0x5E, 0x36, 0x0C, 0x6F]); // dst
    out.extend_from_slice(&[0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]); // src
    out.extend_from_slice(&[0x08, 0x00]); // IPv4
    let ip_len = 20 + 8 + payload_len;
    out.extend_from_slice(&[0x45, 0x00]);
    out.extend_from_slice(&(ip_len as u16).to_be_bytes());
    out.extend_from_slice(&[0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00]);
    out.extend_from_slice(&[10, 0, 0, 1]);             // src 10.0.0.1
    out.extend_from_slice(&[233, 54, 12, 111]);        // dst 233.54.12.111
    out.extend_from_slice(&12345u16.to_be_bytes());    // sport
    out.extend_from_slice(&26400u16.to_be_bytes());    // dport
    out.extend_from_slice(&((8 + payload_len) as u16).to_be_bytes());
    out.extend_from_slice(&[0x00, 0x00]);              // UDP checksum unused
}

fn generate(seed: u64, count: usize, mode: u32) -> Vec<u8> {
    let mut rng = Rng(seed ^ 0xD1B5_4A32_D192_ED03);
    let mut out = Vec::with_capacity(count * 40 + 128);
    let mut idx = 0usize;
    if mode == 0 {
        while idx < count {
            if rng.next() % 100 < 1 {
                out.push([0x00u8, 0x7F, 0xEE, 0xFF][rng.r(4) as usize]);
            } else {
                let t = TYPES[rng.r(22) as usize];
                out.extend_from_slice(&build_message(&mut rng, t, idx as u64));
            }
            idx += 1;
        }
        return out;
    }
    // MoldUDP64 / Ethernet packets with up to 8 messages per packet.
    let mut seq = 1u64;
    while idx < count {
        let take = (count - idx).min(8);
        let mut payload = Vec::with_capacity(take * 52 + 20);
        write_mold_header(&mut payload, seq, take as u16);
        for _ in 0..take {
            let t = TYPES[rng.r(22) as usize];
            let m = build_message(&mut rng, t, idx as u64);
            payload.extend_from_slice(&(m.len() as u16).to_be_bytes());
            payload.extend_from_slice(&m);
            idx += 1;
        }
        if mode == 2 {
            write_eth_ip_udp(&mut out, payload.len());
        }
        out.extend_from_slice(&payload);
        seq += take as u64;
    }
    out
}

// -----------------------------------------------------------------------------
// Chip models
// -----------------------------------------------------------------------------
fn strip_mold(data: &[u8], out: &mut Vec<u8>, frames: &mut u64) {
    // Ethernet mode: walk IPv4 total length. Otherwise assume back-to-back
    // MoldUDP64 packets (20-byte header + [len][msg] entries).
    let mut off = 0usize;
    let eth = data.len() > 14 && data[12] == 0x08 && data[13] == 0x00;
    while off < data.len() {
        if eth {
            if off + 34 > data.len() { break; }
            let ip_total = be(data, off + 16, 2) as usize;
            let frame_len = 14 + ip_total;
            if frame_len < 62 || off + frame_len > data.len() { break; }
            let payload = &data[off + 62..off + frame_len];
            parse_mold_payload(payload, out);
            off += frame_len;
            *frames += 1;
        } else {
            if off + 20 > data.len() { break; }
            let count = be(data, off + 18, 2) as usize;
            let mut p = off + 20;
            let mut ok = true;
            for _ in 0..count {
                if p + 2 > data.len() { ok = false; break; }
                let len = be(data, p, 2) as usize;
                p += 2;
                if p + len > data.len() { ok = false; break; }
                p += len;
            }
            if !ok { break; }
            parse_mold_payload(&data[off + 20..p], out);
            off = p;
            *frames += 1;
        }
    }
}

fn parse_mold_payload(payload: &[u8], out: &mut Vec<u8>) {
    let mut p = 0usize;
    while p + 2 <= payload.len() {
        let len = be(payload, p, 2) as usize;
        p += 2;
        if p + len > payload.len() { break; }
        out.extend_from_slice(&payload[p..p + len]);
        p += len;
    }
}

#[no_mangle]
pub extern "C" fn alloc(size: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(size.max(1));
    let ptr = v.as_mut_ptr();
    std::mem::forget(v);
    ptr
}

#[no_mangle]
pub extern "C" fn dealloc(ptr: *mut u8, size: usize) {
    if !ptr.is_null() {
        unsafe { let _ = Vec::from_raw_parts(ptr, 0, size.max(1)); }
    }
}

#[no_mangle]
pub extern "C" fn version() -> u32 { 0x000300 }

#[no_mangle]
pub extern "C" fn generate_stream(seed: u64, count: usize, mode: u32,
                                  out_ptr: *mut u8, cap: usize) -> usize {
    let v = generate(seed, count, mode);
    if v.len() > cap { return 0; }
    unsafe { std::ptr::copy_nonoverlapping(v.as_ptr(), out_ptr, v.len()); }
    v.len()
}

#[no_mangle]
pub extern "C" fn run_chip(chip: u32, data_ptr: *const u8, len: usize,
                           out_ptr: *mut u8, cap: usize) -> usize {
    if data_ptr.is_null() || len == 0 { return 0; }
    let data = unsafe { std::slice::from_raw_parts(data_ptr, len) };
    let mut parsed = Vec::with_capacity(len + 256);
    let mut st = Stats::default();
    let mut frames = 0u64;
    let (latency, emit_reference) = match chip {
        0 => (0u16, true),   // scalar golden
        1 => (1u16, true),   // rtl-1c
        2 => (2u16, true),   // rtl-2c-safe
        3 => (3u16, true),   // rival-3c
        4 => (2u16, true),   // rival-2c
        5 => (1u16, false),  // lossy: drops reference data
        6 => (3u16, true),   // mold front-end
        7 => (2u16, true),   // book stage
        _ => (1u16, true),
    };
    if chip == 6 {
        let mut raw = Vec::with_capacity(len);
        strip_mold(data, &mut raw, &mut frames);
        if raw.is_empty() {
            // Raw ITCH stream: the front-end is bypassed in this comparison.
            raw.extend_from_slice(data);
            frames = 0;
        }
        parse_itch(&raw, emit_reference, latency, &mut parsed, &mut st);
        st.cycles += frames * 4; // header capture/drain approximation
    } else {
        parse_itch(data, emit_reference, latency, &mut parsed, &mut st);
    }
    let needed = HEADER_SIZE + parsed.len();
    if needed > cap { return 0; }
    let out = unsafe { std::slice::from_raw_parts_mut(out_ptr, needed) };
    for b in out[..HEADER_SIZE].iter_mut() { *b = 0; }
    out[0..4].copy_from_slice(&MAGIC.to_le_bytes());
    out[4..8].copy_from_slice(&chip.to_le_bytes());
    out[8..16].copy_from_slice(&st.count.to_le_bytes());
    out[16..24].copy_from_slice(&st.cycles.to_le_bytes());
    out[24..32].copy_from_slice(&st.consumed.to_le_bytes());
    out[32..40].copy_from_slice(&st.corrupt.to_le_bytes());
    out[40..48].copy_from_slice(&frames.to_le_bytes());
    out[HEADER_SIZE..].copy_from_slice(&parsed);
    needed
}

// -----------------------------------------------------------------------------
// Top-of-book builder (32-byte entries)
// -----------------------------------------------------------------------------
#[derive(Clone, Copy, Default)]
struct BookEntry {
    bid: u32,
    ask: u32,
    last: u32,
    volume: u64,
    orders: u32,
}

#[no_mangle]
pub extern "C" fn build_book(data_ptr: *const u8, len: usize,
                             out_ptr: *mut u8, cap: usize) -> usize {
    if data_ptr.is_null() || len == 0 { return 0; }
    let data = unsafe { std::slice::from_raw_parts(data_ptr, len) };
    let mut book = vec![BookEntry::default(); 4096];
    let mut off = 0usize;
    while off < data.len() {
        let Some((m, used)) = parse_one(data, off) else { break };
        off += used;
        let idx = m.locate as usize;
        if idx >= book.len() { continue; }
        let b = &mut book[idx];
        if m.price > 0 { b.last = m.price; }
        b.volume += m.shares;
        b.orders += 1;
        if matches!(m.t, MSG_ADD_ORDER | MSG_ADD_ORDER_MPID | MSG_TRADE_NON_CROSS) {
            if m.side == b'B' && (b.bid == 0 || m.price > b.bid) { b.bid = m.price; }
            if m.side == b'S' && (b.ask == 0 || m.price < b.ask) { b.ask = m.price; }
        }
    }
    let mut count = 0usize;
    for (i, b) in book.iter().enumerate() {
        if b.orders == 0 { continue; }
        let need = 32 * (count + 1);
        if need > cap { break; }
        let o = unsafe { std::slice::from_raw_parts_mut(out_ptr.add(count * 32), 32) };
        o[0..2].copy_from_slice(&(i as u16).to_le_bytes());
        o[2..4].copy_from_slice(&0u16.to_le_bytes());
        o[4..8].copy_from_slice(&b.bid.to_le_bytes());
        o[8..12].copy_from_slice(&b.ask.to_le_bytes());
        o[12..16].copy_from_slice(&b.last.to_le_bytes());
        o[16..24].copy_from_slice(&b.volume.to_le_bytes());
        o[24..28].copy_from_slice(&b.orders.to_le_bytes());
        o[28..32].copy_from_slice(&0u32.to_le_bytes());
        count += 1;
    }
    count * 32
}
