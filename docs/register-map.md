# Register and port map

Host-facing interfaces of the ChipLab RTL blocks: the narrow host register file, its
Wishbone and Caravel wrappers, the per-locate snapshot block and the performance
counters. Signal names match `rtl/`; the datasheet has the full port tables.

---

## 1. Host register file (`itch_host_wrap`)

32-bit words, **read-only**. `host_addr` is a word address; unmapped addresses read 0.

| Word | Name | Bits | Meaning |
|---|---|---|---|
| 0 | `msg_count` | 31:0 | Parsed messages (same as `status_msg_count`) |
| 1 | `corrupt_count` | 31:0 | Length/corruption errors |
| 2 | `last_id` | 31:24 `last_type` | ITCH opcode of the last message |
| | | 23:16 | zero |
| | | 15:0 `last_locate` | Stock locate |
| 3 | `last_price` | 31:0 | Fixed-point price |
| 4 | `last_shares_lo` | 31:0 | Shares, low word |
| 5 | `last_shares_hi` | 31:0 | Shares, high word |
| 6 | `last_ref_lo` | 31:0 | Order reference, low word |
| 7 | `last_ref_hi` | 31:0 | Order reference, high word |
| 8 | `flags` | 0 `last_valid` | Sticky: at least one message seen |
| | | 1 `last_corrupt` | Last message was corrupt |
| | | 31:2 | zero |
| 9 | `byte_count` | 31:0 | Bytes consumed (`status_byte_count`) |
| 10 | `updates` | 31:0 | Messages latched into the register file |

The `last_*` fields are latched on every `m_axis_order_valid`, including corrupt
messages (check `last_corrupt`). The ingress is AXI4-Stream `DATA_WIDTH` bits (128 by
default, 32 verified) with `tkeep`/`tlast`; `s_axis_tready` is a real handshake.

## 2. Wishbone wrapper (`itch_wishbone_wrap`)

Classic Wishbone slave, 32-bit data, read-only, one-cycle ACK:

| Wishbone | Mapping |
|---|---|
| `wbs_adr_i[6:2]` | word address 0–10 (bits [31:7] and [1:0] are ignored) |
| `wbs_dat_o` | register value for `wbs_adr_i[6:2]` |
| `wbs_ack_o` | asserted for one cycle after `cyc & stb` |
| `wbs_we_i` | writes are acknowledged but ignored |
| `wbs_sel_i` | ignored |

The AXI4-Stream ingress is unchanged. Build the wrapper with
`#(.DATA_WIDTH(32))` for a narrow port.

## 3. Caravel-shaped top (`itch_caravel_wrap`)

| Caravel signal | Mapping |
|---|---|
| `io_in[31:0]` | `s_axis_tdata` |
| `io_in[35:32]` | `s_axis_tkeep` |
| `io_in[36]` | `s_axis_tvalid` |
| `io_in[37]` | `s_axis_tlast` |
| `io_out[0]` | `s_axis_tready` |
| `io_oeb` | `38'h3F_FFFF_FFFE` (only `io_out[0]` driven) |
| `wbs_*` | Wishbone registers as in §2 (`wbs_adr_i[6:2]`) |
| `wb_clk_i` / `wb_rst_i` | clock / active-high reset (`rst_n = ~wb_rst_i`) |
| `la_data_in`, `la_oenb` | unused; `la_data_out = 0` |
| `user_irq` | `3'b000` |

This is the boundary shape; no Caravel harness run has been done.

## 4. Book snapshot (`itch_book_snapshot`)

A per-locate table with a direct read port (no address map):

- Write side: `upd_valid` + `upd_locate[LOC_AW-1:0]` + top-of-book, last-trade,
  volume and top-4 depth fields.
- Read side: drive `rd_locate` with `rd_valid`; one clock later
  `snap_valid` is high and `snap_locate`, `snap_hit`, `snap_bid_price`,
  `snap_bid_shares`, `snap_ask_price`, `snap_ask_shares`, `snap_last_price`,
  `snap_last_shares`, `snap_volume`, `snap_bid_p0..p3`, `snap_bid_s0..s3`,
  `snap_ask_p0..p3`, `snap_ask_s0..s3` are valid and stable until the next read.
- `snap_hit` is low for a locate that has never been updated; `updates` counts
  applied events.
- Size: `LOCATES × (2 × 4 × 96 + 3 × 96 + 64)` bits ≈ 18 Kbit at 16 locates.

## 5. Performance counters (`itch_metrics`)

| Port | Meaning |
|---|---|
| `msg_count`, `byte_count` | Totals since reset |
| `gap_count`, `drop_count` | Pulses on `gap_pulse` / `drop_pulse` |
| `cycle_count` | Free-running clock cycles (host derives rates) |
| `occupancy_max` | Maximum observed `occupancy` input |
| `hist0..hist7` | Inter-message gap histogram: 0, 1, 2, 3, 4–7, 8–15, 16–31, ≥32 cycles |

Derived rates: `messages/s = Δmsg_count × f_clk / Δcycle_count`; mean gap in cycles
= `Δcycle_count / Δmsg_count`.

## 6. Mold / arbiter status

| Signal | Meaning |
|---|---|
| `expected_seq` | Next expected MoldUDP64 sequence |
| `gap` (pulse), `gaps` | Out-of-order frame detected / count |
| `req_valid`, `req_seq`, `req_count` | Retransmit request (16-bit saturating count) |
| `abandon` (pulse), `abandoned` | Timeout resync / count |
| `dropped_a`, `dropped_b`, `overflows` | Per-feed drops and buffer overflows |
| `frames_a`, `frames_b` | Frames accepted per feed |
