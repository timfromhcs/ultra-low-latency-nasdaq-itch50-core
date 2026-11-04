# ChipLab ITCH-50 — Datasheet

**Part:** `ultra_low_latency_nasdaq_itch50_cutthrough` (parser) and
`itch_top_book` (parser + multi-symbol top-of-book)
**Version:** 0.3.1
**Status:** tapeout-ready RTL, **not fabricated**, **no physical sign-off**
**Protocol:** NASDAQ TotalView-ITCH 5.0, all 22 official message types

---

## 1. Overview

The core parses a byte stream of ITCH 5.0 messages from AXI4-Stream beats into a
registered 80-byte internal record per message, with no bubble insertion and no
per-message stall. A second wrapper adds a per-locate order book with a top-4
depth snapshot per message.

Two egress paths exist:

| Path | Latency | Use |
|---|---|---|
| Registered (`m_axis_order_*`) | 2 clocks from `s_axis_tdata`, 1 clock from the internal window register | Normal integration, timing-closed |
| Asynchronous bypass (`raw_*`) | same cycle as the window register | Lowest latency, requires a tight downstream capture stage |

## 2. Feature summary

- 128-bit AXI4-Stream ingress (the `DATA_WIDTH` parameter also supports 32-bit
  ingress, verified through the Wishbone wrapper), with `tkeep`/`tlast`, unaligned
  message boundaries resolved across beats by a 512-bit sliding window.
- All 22 ITCH 5.0 opcodes decoded, including the administrative/reference set
  (`S R H Y L V W K J h`) and the trading set (`A F E C X D U P Q B N`).
- Full payload preserved (`m_payload[511:0]`, `m_msg_len[7:0]`); corrupt or
  truncated messages are flagged (`m_error_corrupt`) and counted
  (`status_corrupt_count`).
- Order book: 16 locates × 16 price levels per side, 256 order slots, 4-way
  set-associative lookup, top-4 depth per side, last trade and volume.
- Risk checks per event: maximum shares per order (`cfg_max_shares`) and price
  collar versus the last trade (`cfg_collar`), with a reject counter.
- Performance counters: message/byte totals, gap/drop pulses, free-running cycle
  counter, maximum queue occupancy, 8-bin inter-message gap histogram.
- Host snapshot table: per-locate top-of-book, last trade, volume and top-4 depth with
  a one-cycle registered read port.
- MoldUDP64 front-end (Ethernet/IP/UDP → sequence tracking) and a two-feed A/B
  arbiter with retransmit request, replay recovery and timeout resync.

## 3. Electrical / timing targets

| Parameter | Value | Note |
|---|---|---|
| Clock | 322.26 MHz (3.10 ns) | Model target from `docs/timing_cutthrough.*` |
| Reset | Active-low synchronous `rst_n` | Must be held through book table clear (~800 cycles) |
| Ingress | 128-bit/beat, one message may span beats | `tready` is asserted while the shifter has room |
| Sustained rate | 1 parsed message per clock (book: 1 event/clock) | Verified back-to-back |
| Pipeline depth | 2 clocks registered | 1 clock from window register |
| Optional ingress skid | `INGRESS_SKID=1`: 2-entry elastic buffer | At most +1 beat latency, zero loss |
| I/O | All single clock domain | No CDC inside the core |

> Fmax and area are **model numbers**. There is no OpenSTA/LibreLane sign-off in this
> repository; do not quote them as silicon results. Pre-PnR Sky130 runs (2026-11-03/04)
> measure WNS −9.14 ns at 3.10 ns for the raw parser (≈81.5 MHz), −8.62 ns for the
> 128-bit wrapper (≈85.3 MHz) and **−6.55 ns for the 32-bit wrapper (≈103.7 MHz)**;
> all at the ss corner. These are honest pre-place-and-route numbers, not sign-offs.

## 4. Area estimate

Reduced configuration (`ORDERS=32`, `LOCATES=4`, `LEVELS=4`), Yosys 0.52 generic
mapping, **62,017 cells / 98,322 wires** (`reports/synth_book.json`). This is an
estimate for relative sizing only — no standard-cell library, no timing closure.

## 5. Interface — parser (`ultra_low_latency_nasdaq_itch50_cutthrough`)

### Clock and reset
| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |

### AXI4-Stream slave
| Signal | Dir | Width | Description |
|---|---|---|---|
| `s_axis_tdata` | in | 128 | Byte stream, little-endian lanes |
| `s_axis_tkeep` | in | 16 | Valid bytes per beat |
| `s_axis_tvalid` | in | 1 | Beat valid |
| `s_axis_tlast` | in | 1 | Last beat of a MoldUDP64 frame |
| `s_axis_tready` | out | 1 | Core can accept a beat |

### Message egress (registered)
| Signal | Dir | Width | Description |
|---|---|---|---|
| `m_axis_order_valid` | out | 1 | One-clock pulse per parsed message |
| `m_order_type` | out | 8 | ITCH opcode |
| `m_stock_locate` | out | 16 | Stock locate |
| `m_tracking_number` | out | 16 | Tracking number |
| `m_timestamp` | out | 48 | Nanoseconds since midnight |
| `m_order_ref_num` | out | 64 | Order reference |
| `m_new_order_ref_num` | out | 64 | Replacement reference |
| `m_side` | out | 8 | `B` / `S` |
| `m_shares` | out | 64 | Shares |
| `m_stock` | out | 64 | Stock symbol, 8 bytes |
| `m_price` | out | 32 | Fixed-point price |
| `m_match_number` | out | 64 | Match number |
| `m_mpid` | out | 32 | MPID |
| `m_printable` | out | 1 | Trade printable flag |
| `m_is_trade` / `m_is_reference` / `m_is_drop` | out | 1 | Message class |
| `m_error_corrupt` | out | 1 | Length/corruption error |
| `m_payload` | out | 512 | Full message bytes |
| `m_msg_len` | out | 8 | Message length |
| `m_event_code` / `m_ref_value` | out | 8 / 32 | Event code and reference value |

### Status (free-running counters, cleared by `rst_n`)
`status_msg_count`, `status_byte_count`, `status_corrupt_count`,
`status_frame_count`, `status_beat_count`, `status_last_pulse`,
`status_buf_count[7:0]` (shifter occupancy).

### Asynchronous bypass
`raw_order_valid`, `raw_order_data[483:0]`, `raw_stock_locate_pre_trigger[15:0]`,
`raw_pre_trigger_valid`, `raw_msg_length[7:0]`, `raw_is_trade`,
`raw_is_reference`, `raw_is_drop`, `raw_is_corrupt`, `raw_payload[511:0]`.

## 6. Interface — parser + book (`itch_top_book`)

Everything above (subset), plus:

| Signal | Dir | Width | Description |
|---|---|---|---|
| `bbo_valid` | out | 1 | Book updated for this message |
| `bbo_locate` | out | 16 | Stock locate |
| `bbo_bid_price` / `bbo_ask_price` | out | 32 | Best bid / ask |
| `bbo_bid_shares` / `bbo_ask_shares` | out | 64 | Size at the touch |
| `bbo_last_price` / `bbo_last_shares` | out | 32 / 64 | Last trade |
| `bbo_volume` | out | 64 | Cumulative volume |
| `bbo_bid_p0..p3`, `bbo_ask_p0..p3` | out | 32 each | Top-4 depth prices |
| `bbo_bid_s0..s3`, `bbo_ask_s0..s3` | out | 64 each | Top-4 depth sizes |
| `cfg_max_shares` | in | 64 | Per-order share limit (0 = off) |
| `cfg_collar` | in | 32 | Price collar vs. last trade (0 = off) |
| `risk_rejects` | out | 32 | Rejected events |
| `metrics_*` | out | — | See `api.md`; counters above |
| `ready` | out | 1 | Book tables cleared; parser released |

`ready` is low for roughly 800 clocks after reset while the book clears its tables.
Gate downstream logic on `ready`, and keep ingress idle until it is high; messages
arriving earlier are otherwise accepted by the parser but not booked.

## 7. Verification evidence

| Check | Result | Artifact |
|---|---|---|
| Full-field regression, 1,000,000 messages | 0 mismatches | `tb/sim_main.cpp`, `reports/` |
| Parser → book, 152 ITCH messages | 0 mismatches, 152/4800 metrics | `tb/test_book_top.py` |
| Book, 400 random + 100 back-to-back | 0 mismatches, 1 event/clock | `tb/test_book.py` |
| Risk checks | rejects share/collar violations | `tb/test_book.py` |
| Mold multi-frame, 5 frames | 28 records, 1 gap, 1 drop | `tb/test_multi.py` |
| A/B arbiter | selection, gap request, replay, multi-gap [1..8], abandon | `tb/test_arbiter.py` |
| Two-feed system | 2 Ethernet feeds → 10 records, 1 gap | `tb/test_ab_system.py` |
| RTL ↔ WASM equivalence | 100,000 records, every field equal | weekly `equivalence` job |
| Mutation (book) | 9/9 mutants killed | `reports/mutation_book.json` |
| Formal | protocol invariants proven (Z3/CVC5) | `formal/`, weekly job |

## 8. Known limitations

See `errata.md`. In short: no 100G MAC, no PCIe/DMA, no physical sign-off, no
fabricated silicon, and the book is a 16-locate/16-level model rather than a
full-depth L3 book.

## 9. Ordering and support

This is an open-source repository: <https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core>.
License and contribution terms are in `LICENSE.md` and `CONTRIBUTING.md`.
