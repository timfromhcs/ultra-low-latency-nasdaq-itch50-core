# MoldUDP64 multi-frame back-pressure — design note (R1)

## Current status

- **Single frame end-to-end: PASS** (`tb/test_mold_pipeline.py`).
- **Header filter + sequence gap + drop: PASS** (`tb/test_mold.py`).
- **Multi-frame back-to-back: OPEN.** A second frame can be accepted while the
  depacketizer still owns frame-end state; the first payload prefix is then misaligned.

This is deliberately not hidden: README, `LONG_TERM_PLAN.md` and `AUTONOMOUS_PLAN_V2.md`
list it as R1.

## Why it happens

The front-end emits payload bytes only after a header decision, while the depacketizer
has its own `msg_count`, `msgs_left` and output reblocking state. `frame_start` must be
aligned to the **first payload beat**, not to the earlier header decision, and a new
frame must not overwrite a depacketizer that still has bytes in flight. The current
single-frame test proves the datapath; the multi-frame test exposes the handoff race.

## Fix (next increment)

1. Add `rtl/axis_skid_buffer.sv` (already implemented and tested: 200 random beats,
   no loss, stable under random `tready`).
2. Extend the skid buffer with sideband `frame_start` / `frame_end` bits so the frame
   markers travel with the payload data.
3. Insert it between `moldudp64_frontend` and `moldudp64_depacketizer`.
4. Change the depacketizer to load `msgs_left` on the skid's `frame_start`, and to
   return `frame_ready` only when `msgs_left==0 && msg_left==0 && count==0 && !m_axis_tvalid`.
5. Test: 4 frames back-to-back (1, 9, 17, 25), one missing sequence, one invalid port,
   one final good frame; require 32 exact records and one gap pulse.
6. Formal: no frame overlap, no byte loss, `frame_start` exactly once per valid frame.

## Acceptance

- 4-frame back-to-back and 64-frame stress: 0 mismatches.
- `reports/sim_1m.txt` unchanged.
- Verilator lint 0 warnings.
- If the skid stage is not integrated, the README must keep saying "single-frame only".
