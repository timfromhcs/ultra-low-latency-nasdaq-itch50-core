# Integration guide

How to put the parser, the book and the Mold front-end into a design, and how to
drive them in simulation. The numbers and signal names here match the RTL in
`rtl/`; `datasheet.md` has the full port tables.

---

## 1. Pick your boundary

| You have | Use | Top module |
|---|---|---|
| A raw ITCH byte stream in AXI4-Stream beats | Parser | `ultra_low_latency_nasdaq_itch50_cutthrough` (`rtl/itch_top.sv`) |
| Raw ITCH bytes and want per-message BBO | Parser + book | `itch_top_book` (`rtl/itch_top_book.sv`) |
| Ethernet frames with MoldUDP64 | Two-feed front-end | `mold_ab_system` (`rtl/mold_ab_system.sv`) |
| One Mold feed | Single pipeline | `moldudp64_pipeline` (`rtl/moldudp64_pipeline.sv`) |
| A lossy/redundant pair of feeds | Arbiter + replay | `mold_feed_arbiter` (`rtl/mold_feed_arbiter.sv`) |

## 2. Minimal parser instantiation

```systemverilog
ultra_low_latency_nasdaq_itch50_cutthrough #(
  .DATA_WIDTH(128)
) u_parse (
  .clk(clk),
  .rst_n(rst_n),
  .s_axis_tdata(s_tdata),
  .s_axis_tkeep(s_tkeep),
  .s_axis_tvalid(s_tvalid),
  .s_axis_tlast(s_tlast),
  .s_axis_tready(s_tready),
  .m_axis_order_valid(msg_valid),
  .m_order_type(msg_type),
  .m_stock_locate(msg_locate),
  .m_price(msg_price),
  .m_shares(msg_shares),
  .m_side(msg_side),
  .m_order_ref_num(msg_ref),
  .m_new_order_ref_num(msg_new_ref),
  .m_error_corrupt(msg_corrupt),
  .status_msg_count(msg_count)
  // remaining outputs may be left unconnected
);
```

Rules that matter:

1. **One clock domain.** There is no CDC inside the core. `rst_n` is synchronous and
   active-low; hold it for at least 8 clocks.
2. **`tready` is a real handshake.** A beat counts only when `tvalid && tready`. The
   shifter stalls when a message exceeds its 512-bit window, and the parser holds
   `tready` low until the window drains.
3. **`tlast` marks the end of a Mold frame.** The parser uses it for
   `status_frame_count`/`status_last_pulse`; message parsing itself works from the
   byte stream and does not require `tlast`. Drive it from the depacketizer if you
   have one, or tie it to the final beat of your capture block.
4. **Corrupt messages still pulse `m_axis_order_valid`.** Filter on
   `!m_error_corrupt` if you index tables with their fields, or count them as drops
   (the book does exactly that).

**Narrow physical wrapper:** `itch_host_wrap` keeps the AXI4-Stream ingress
(`DATA_WIDTH` 128 by default, 32 verified) and replaces the wide debug record bus with
a 32-bit host register port (counters, last message type/locate/price/shares/ref,
valid/corrupt flags). Use it for place-and-route runs where the ~1,100-pin debug bus
would cause pin congestion; `itch_wishbone_wrap` exposes the same registers over a
classic Wishbone slave for Caravel-style management. Word map is in the module header;
`openlane/sky130_wrap.json` targets it.

## 3. Parser + book

```systemverilog
itch_top_book u_book (
  .clk(clk), .rst_n(rst_n),
  .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep),
  .s_axis_tvalid(s_tvalid), .s_axis_tlast(s_tlast), .s_axis_tready(s_tready),
  .bbo_valid(bbo_valid), .bbo_locate(bbo_locate),
  .bbo_bid_price(bid), .bbo_bid_shares(bid_sz),
  .bbo_ask_price(ask), .bbo_ask_shares(ask_sz),
  .bbo_last_price(last), .bbo_last_shares(last_sz), .bbo_volume(vol),
  .bbo_bid_p0(bid_p0), .bbo_bid_s0(bid_s0), /* p1..p3, s1..s3 */
  .bbo_ask_p0(ask_p0), .bbo_ask_s0(ask_s0), /* p1..p3, s1..s3 */
  .cfg_max_shares(64'd0),        // 0 disables the share limit
  .cfg_collar(32'd0),            // 0 disables the collar
  .risk_rejects(risk_rejects),
  .metrics_msg_count(perf_msgs),
  .metrics_byte_count(perf_bytes),
  .metrics_gap_count(perf_gaps),
  .metrics_drop_count(perf_drops),
  .metrics_cycle_count(perf_cycles),
  .metrics_occupancy_max(perf_occ_max),
  .metrics_hist0(hist0), /* ... hist7 */
  .status_msg_count(status_msgs),
  .status_corrupt_count(status_corrupt),
  .ready(book_ready)
);
```

**Startup:** `ready` is low for ~800 clocks while the book clears its tables and the
parser is held in reset. Do not send traffic before `ready`; the parser will accept
it but the book will not have a valid state. In simulation, wait for `ready` before
the first beat.

**Timing isolation:** `itch_top_book #(.INGRESS_SKID(1))` (default `0`) inserts the
2-entry `axis_skid_buffer` in front of the parser. It is functionally transparent
(same BBO, same counters) and adds at most one beat of latency; use it when the input
path, not the book, is the critical path. `tb/run_book_top_skid_cocotb.py` runs the
same 152-message test against both builds with periodic input gaps.

**Book scope:** 16 stock locates, 16 price levels per side, 256 orders (4-way
associative per 64-slot set), top-4 depth on the outputs. Events for other locates or
beyond the level capacity are counted in `drops_overflow`/`level_overflow` (internal)
and do not corrupt the existing book.

## 4. MoldUDP64 front-end

The pipeline takes Ethernet AXI4-Stream (64-bit data, 8-bit keep, `tlast` at the end of
frame) and produces the ITCH byte stream plus sequence status:

| Signal | Meaning |
|---|---|
| `cfg_initial_seq` | First expected Mold sequence number |
| `expected_seq` | Next expected sequence after the last accepted frame |
| `gap` | Pulse: the frame was not the expected sequence |
| `gaps` | Gap count |
| `req_valid` / `req_seq` / `req_count` | Retransmit request (arbiter recovery mode) |
| `abandon` / `abandoned` | Timeout resync events |

For a redundant A/B pair, use `mold_ab_system`: two full Ethernet pipelines feed
`mold_feed_arbiter`, which selects the first feed that has the expected sequence,
and in `cfg_recovery_en` mode requests the missing range, drops the out-of-order
frames, accepts the replay, and abandons to a force-accept after a 256-cycle
timeout. Downstream back-pressure is honored end to end (`m_axis_tready` stalls the
depacketizer instead of dropping bytes).

**Contract with your retransmitter:** the block drives `req_valid`, `req_seq` and
`req_count` (16-bit saturating) for one cycle and expects the requested sequence range
to reappear on either feed within 256 clocks. This is the boundary to a real network
stack; the RTL does not speak a retransmit protocol itself.

## 5. Host book snapshots

`itch_book_snapshot` mirrors the book into a per-locate table so a host can read the
current state without replaying events:

```systemverilog
itch_book_snapshot #(.LOCATES(16)) u_snap (
  .clk(clk), .rst_n(rst_n),
  .upd_valid(bbo_valid),
  .upd_locate(bbo_locate[3:0]),     // LOC_AW = clog2(LOCATES)
  .upd_bid_price(bbo_bid_price), .upd_bid_shares(bbo_bid_shares),
  .upd_ask_price(bbo_ask_price), .upd_ask_shares(bbo_ask_shares),
  .upd_last_price(bbo_last_price), .upd_last_shares(bbo_last_shares),
  .upd_volume(bbo_volume),
  .upd_bid_p0(bbo_bid_p0), /* p1..p3, s0..s3, ask... */
  .rd_valid(host_rd), .rd_locate(host_locate),
  .snap_valid(snap_valid), .snap_hit(snap_hit),
  .snap_locate(snap_locate), .snap_bid_price(snap_bid), /* ... */
  .updates(snap_updates)
);
```

Present `rd_locate` with `rd_valid`; the snapshot is registered and appears one clock
later with `snap_valid`, holding until the next read. `snap_hit` is low for a locate
that has never been updated, and `updates` counts applied events. The table costs about
18 K flip-flops at 16 locates × 4 levels — put it at the host bridge, not in the feed
path.

## 6. Performance counters

`itch_metrics` is clocked with the pipeline and resets with `rst_n`. Poll it from a
management bus or a slow clock domain (the counters are static for many cycles at
typical rates, but if you cross domains, sample through a handshake or a gray-coded
snapshot).

| Derived value | Formula |
|---|---|
| Messages/s | `Δmetrics_msg_count × f_clk / Δmetrics_cycle_count` |
| Bytes/s | `Δmetrics_byte_count × f_clk / Δmetrics_cycle_count` |
| Mean gap (cycles) | `Δmetrics_cycle_count / Δmetrics_msg_count` |
| Drop rate | `Δmetrics_drop_count / Δmetrics_msg_count` |
| Bimodality | compare `hist0` (back-to-back) with `hist7` (≥ 32-cycle gaps) |

`metrics_gap_count` is fed from the link-layer gap signal where one exists. In
`itch_top_book` it is tied low (gaps are a Mold concept) and corrupt messages are
counted as drops. Instantiate `itch_metrics` yourself if your pipeline has a
different definition of gap/drop.

## 7. Simulation

```bash
# Lint (Verilator, 0 warnings required)
make lint

# Python reference model + 1M full-field regression
make verify-deep

# Cocotb unit/integration suites (Icarus)
make cocotb

# One suite
python3 tb/run_book_top_cocotb.py
```

The Cocotb runners accept `CHIPLAB_RTL` to point at a different `rtl/` directory.
Vectors are plain files: `stream.bin` (concatenated ITCH messages) and
`expected.bin` (80-byte records), generated by `tb/itch_model.py`.

## 8. Synthesis

```bash
# Book area estimate (reduced 32/4/4 config)
bash scripts/synth_book.sh
```

Output: `reports/synth_book.json` + `reports/synth_book_32_4_4.log`. These are generic
Yosys cell counts. For a real target, map to your library and run timing; there is no
OpenSTA/LibreLane result in this repository yet.
