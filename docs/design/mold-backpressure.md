# MoldUDP64 multi-frame back-pressure — resolved (v0.3.2 work)

## Status

- **5 frames back-to-back PASS**: 4 valid frames, one sequence gap, one dropped-port
  frame → 28 records, 1 gap pulse, 1 drop pulse, 0 mismatches
  (`tb/test_mold_multi.py`, `tb/run_multi_cocotb.py`).
- Single-frame pipeline and header/filter tests still pass.
- No skid stage was required for functional correctness; the front-end now holds a
  beat under back-pressure per the AXI4-Stream rules. `axis_skid_buffer.sv` remains
  available for timing isolation at higher clock rates.

## Root causes found

The original "multi-frame race" was three distinct RTL bugs, not one protocol issue:

1. **`tlast` was cleared while a beat was held.** The repacker registered `tlast` for
   one cycle, then the next cycle's default `m_axis_tlast <= 0` erased it even though
   `tvalid` was still asserted (downstream `tready=0`). The last beat handshook with
   `tlast=0`, so the next stage never saw a frame end.
2. **A presented beat could be dropped.** `if (!do_emit && out_ready) m_axis_tvalid <= 0`
   deasserted `tvalid` when no new beat was being produced, even without a handshake.
   The held last beat vanished, losing bytes and the frame boundary.
3. **`frame_start` was not handshake-qualified.** `frame_start = tvalid && !in_frame`
   re-fired on every cycle a beat was held. It reset the depacketizer buffer with a
   partial beat and could restart a frame mid-stream.

A fourth, latent issue: when the frame's last payload byte landed exactly on a full
16-byte beat, no explicit `tlast` was produced at all (the beat was emitted in
`ST_STREAM`, and `ST_FLUSH` then completed with an empty buffer).

## Fixes

- Front-end holds `tvalid/tdata/tkeep/tlast` stable until `tready`; `tlast` is only
  cleared on the handshake.
- `final_emit = do_emit && (next_out_count == 0) && input_done_now` marks the true
  last beat, including the full-beat boundary case.
- `frame_start` and `frame_end` are handshake-qualified (`tvalid && tready`).
- New `frame_end` sideband releases the depacketizer; it discards trailing Ethernet
  padding after the last message instead of filling its buffer.
- The depacketizer emits its own `tlast` from `msgs_left == 0 && msg_left == 0`, so it
  does not depend on the front-end's `tlast` being cycle-aligned through its buffer.
- `frame_ready` remains the front-end's explicit "can accept a new frame" signal.

## Acceptance

- 5-frame back-to-back: 28 records, 1 gap, 1 drop, 0 mismatches.
- Single-frame, header filter, skid: PASS.
- Verilator lint: 0 warnings.
- CI runs `tb/run_multi_cocotb.py` on Icarus.

## Still open

- 64-frame stress + loss/gap recovery.
- Ethernet padding beyond the UDP length is discarded by frame end; a strict
  UDP-length trim is a future refinement.
- No 100G MAC integration; the ingress is a testbench model.
