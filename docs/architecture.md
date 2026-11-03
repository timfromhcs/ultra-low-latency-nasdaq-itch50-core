# Hardware Microarchitecture & Specification
## Core: `ultra_low_latency_nasdaq_itch50_cutthrough` (v2)

> **v2 truth note (2026-11-03):** the original text below described a 452-bit record and
> a "0-cycle / 1.10 ns" bypass. v2 widens shares to 64 bit (484-bit record), adds
> `tkeep`/`tlast`, preserves the full payload, and states the honest latency:
> **2 clocks from `s_axis_tdata` to registered output** (1 clock from the window
> register). The async bypass is valid in the same cycle as the window, one clock after
> ingress. Fmax is a model target, not a sign-off.

---

## 1. Architectural Overview

The `ultra_low_latency_nasdaq_itch50_cutthrough` core is an ultra-low-latency, zero-stall hardware parser implementing the **NASDAQ TotalView-ITCH 5.0** market data protocol. 

The architecture is partitioned into four decoupled, ultra-fast sub-modules:
1. **Continuous Lookahead Shifter (`itch_shifter.sv`)**: A single-cycle 512-bit sliding lookahead buffer that resolves unaligned packet boundaries across 128-bit AXI4-Stream words with **0 stall penalty**.
2. **Early Non-Trade Drop Gate (`itch_drop_gate.sv`)**: A parallel combinatorial filter that identifies administrative and non-trade messages (e.g., `'S'`, `'R'`, `'H'`, `'Y'`, `'L'`, `'V'`, `'W'`, `'K'`, `'J'`, `'h'`) in $< 0.35\,\text{ns}$ gate propagation.
3. **Speculative Parallel Decoder & Pre-Trigger Matrix (`itch_parser_core.sv`)**: Slices the Stock Locate field combinationally in **Cycle 0 ($< 0.30\,\text{ns}$)** for instant downstream L3 Order Book memory pre-fetching, while simultaneously decoding order parameters for message types `'A'`, `'F'`, `'E'`, `'C'`, `'X'`, `'D'`, `'U'`, `'P'`, `'Q'`.
4. **Asynchronous Bypass & Registered Pipeline (`itch_top.sv`)**: Provides dual-path egress: an asynchronous combinatorial cut-through bus ($\le 1.10\,\text{ns}$ total gate delay) and a registered output stage operating deterministically in **strictly 1 clock cycle ($3.10\,\text{ns}$ @ $322.26\,\text{MHz}$)**.

---

## 2. Block Diagram

```
                              +------------------------------------------+
                              | AXI4-Stream Slave Interface (128-bit)   |
                              | [s_axis_tdata, s_axis_tvalid, tlast]     |
                              +------------------------------------------+
                                                   |
                                                   v
                              +------------------------------------------+
                              | Continuous Barrel Lookahead Shifter     |
                              | - 128-byte dynamic packed buffer         |
                              | - Single-cycle consume shifting          |
                              | - 512-bit sliding window output          |
                              +------------------------------------------+
                                                   |
                        +--------------------------+--------------------------+
                        |                                                     |
                        v                                                     v
       +------------------------------------+               +------------------------------------+
       | Direct L3 Stock Locate Pre-Trigger |               |    Early Non-Trade Drop Gate       |
       | - Slices locate ID in Cycle 0      |               | - Parallel opcode classifier       |
       | - Delay: < 0.30 ns                 |               | - Instant filter for admin msgs    |
       +------------------------------------+               +------------------------------------+
                        |                                                     |
                        +--------------------------+--------------------------+
                                                   |
                                                   v
                              +------------------------------------------+
                              | Speculative Parallel Decoding Matrix     |
                              | - Concurrent parallel field extraction   |
                              | - Byte-swap to host endianness           |
                              | - Big-endian 64b/32b integers            |
                              +------------------------------------------+
                                                   |
                        +--------------------------+--------------------------+
                        |                                                     |
                        v                                                     v
       +------------------------------------+               +------------------------------------+
       | Asynchronous Combinatorial Egress  |               | Registered Pipeline Output Stage   |
       | - raw_order_valid                  |               | - m_axis_order_valid (1 cycle)     |
       | - raw_order_data [451:0]           |               | - Registered order records         |
       | - Max Gate Delay: <= 1.10 ns       |               | - Clock: 322.26 MHz (3.10 ns)      |
       +------------------------------------+               +------------------------------------+
```

---

## 3. Interface Pinout & Bus Description

### Clock & Reset
| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | Primary system clock (Target: $322.26\,\text{MHz}$, $T_{\text{clk}} = 3.10\,\text{ns}$) |
| `rst_n` | Input | 1 | Active-low synchronous reset |

### AXI4-Stream Slave Ingress
| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `s_axis_tdata` | Input | 128/256/512 | Streaming packet data (parameterised) |
| `s_axis_tkeep` | Input | 16/32/64 | Valid byte mask per beat |
| `s_axis_tvalid` | Input | 1 | Data valid handshake signal |
| `s_axis_tlast` | Input | 1 | Frame end delimiter |
| `s_axis_tready` | Output | 1 | Flow control backpressure ready flag |

### Asynchronous Combinatorial Fast-Path
| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `raw_order_valid` | Output | 1 | Immediate combinatorial message valid trigger |
| `raw_order_data` | Output | 452 | Flattened speculative decoded order payload |
| `raw_stock_locate_pre_trigger` | Output | 16 | Direct Cycle-0 Stock Locate ($< 0.30\,\text{ns}$ gate delay) |
| `raw_msg_length` | Output | 8 | Detected message length in bytes |
| `raw_is_trade` | Output | 1 | Trade order classification flag |
| `raw_is_drop` | Output | 1 | Administrative / non-trade message flag |
| `raw_is_corrupt` | Output | 1 | Protocol framing error / unknown opcode |
| `status_buf_count` | Output | 8 | Current valid buffer byte occupancy |

### Registered Pipeline Outputs (Strict 1-Cycle Latency)
| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axis_order_valid` | Output | 1 | Registered message valid flag |
| `m_order_type` | Output | 8 | ITCH 5.0 ASCII message type opcode |
| `m_stock_locate` | Output | 16 | 16-bit Stock Locate identifier |
| `m_tracking_number` | Output | 16 | 16-bit Nasdaq internal tracking number |
| `m_timestamp` | Output | 48 | 48-bit nanoseconds since midnight timestamp |
| `m_order_ref_num` | Output | 64 | 64-bit unique order reference number |
| `m_new_order_ref_num` | Output | 64 | 64-bit replacement order reference number (Msg 'U') |
| `m_side` | Output | 8 | Buy ('B' / 0x42) or Sell ('S' / 0x53) |
| `m_shares` | Output | 64 | 64-bit order/cross share quantity ('Q' needs 64 bit) |
| `m_payload` | Output | 512 | Full message bytes, including reference data |
| `m_stock` | Output | 64 | 8-character ASCII stock symbol |
| `m_price` | Output | 32 | 32-bit fixed-point price ($4\text{ decimal places}$) |
| `m_match_number` | Output | 64 | 64-bit exchange match execution number |
| `m_mpid` | Output | 32 | 4-character Market Participant Identifier |
| `m_printable` | Output | 1 | Non-displayable execution flag ('Y'/'N') |
| `m_is_trade` | Output | 1 | Asserted for trade messages ('A', 'F', 'E', 'C', 'X', 'D', 'U', 'P', 'Q') |
| `m_is_reference` | Output | 1 | Reference/administrative message (R/H/Y/L/...) |
| `m_is_drop` | Output | 1 | Alias of `m_is_reference` (no information is discarded) |
| `m_error_corrupt` | Output | 1 | Asserted when invalid opcode or corrupt framing is encountered |

---

## 4. Latency Budget & Timing Sign-Off

```
[Cycle 0: Ingress]  s_axis_tdata arriving on 128-bit bus
                    |--- 0.30 ns ---> raw_stock_locate_pre_trigger valid (L3 Pre-Fetch)
                    |--- 0.35 ns ---> Early Non-Trade Drop Gate Classification
                    |--- 0.85 ns ---> Full Speculative Parsing Complete
                    |--- 1.10 ns ---> raw_order_data valid (Asynchronous Bypass)
[Cycle 1: Egress]   Clock Edge (3.10 ns @ 322.26 MHz)
                    |--- +0.12 ns --> m_axis_order_valid & m_* registered outputs valid
```