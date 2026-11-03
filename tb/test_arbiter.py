# =============================================================================
# File: tb/test_arbiter.py
# Description: A/B Mold feed arbitration: sequence-based selection, gap, the
#              redundancy window and byte-exact forwarding.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

DATA_BYTES = 16
TIMEOUT = 64


def frame(seq, beats=3):
    out = bytearray()
    for i in range(beats):
        out += bytes([(seq + i) & 0xFF]) * DATA_BYTES
    return bytes(out)


async def send_frame(dut, feed, seq, count, data):
    p = "a_" if feed == "a" else "b_"
    tdata = getattr(dut, p + "tdata")
    tkeep = getattr(dut, p + "tkeep")
    tvalid = getattr(dut, p + "tvalid")
    tlast = getattr(dut, p + "tlast")
    tready = getattr(dut, p + "tready")
    getattr(dut, p + "seq").value = seq
    getattr(dut, p + "count").value = count

    off = 0
    while off < len(data):
        chunk = data[off:off + DATA_BYTES]
        off += len(chunk)
        pad = chunk + b"\x00" * (DATA_BYTES - len(chunk))
        # Present the beat at the falling edge so the DUT has a full setup
        # window before the accepting rising edge.
        await FallingEdge(dut.clk)
        tdata.value = int.from_bytes(pad, "little")
        tkeep.value = (1 << len(chunk)) - 1
        tvalid.value = 1
        tlast.value = 1 if off >= len(data) else 0
        guard = 0
        while int(tready.value) == 0:
            await FallingEdge(dut.clk)
            guard += 1
            if guard > 20000:
                raise TimeoutError("feed backpressure stuck")
        await RisingEdge(dut.clk)
    tvalid.value = 0
    tlast.value = 0
    await RisingEdge(dut.clk)


async def wait_frames(dut, got, n, cycles=5000):
    for _ in range(cycles):
        if len(got) >= n:
            return
        await RisingEdge(dut.clk)
    raise TimeoutError(f"expected {n} output frames, got {len(got)}")


@cocotb.test()
async def test_ab_selection(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.initial_seq.value = 1
    dut.recovery_en.value = 0
    dut.a_tvalid.value = 0
    dut.a_tlast.value = 0
    dut.a_tdata.value = 0
    dut.a_tkeep.value = 0
    dut.a_seq.value = 0
    dut.a_count.value = 0
    dut.b_tvalid.value = 0
    dut.b_tlast.value = 0
    dut.b_tdata.value = 0
    dut.b_tkeep.value = 0
    dut.b_seq.value = 0
    dut.b_count.value = 0
    dut.m_tready.value = 1
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    got = []
    cur = bytearray()

    async def monitor():
        while True:
            await FallingEdge(dut.clk)
            if int(dut.m_tvalid.value) and int(dut.m_tready.value):
                keep = int(dut.m_tkeep.value)
                data = int(dut.m_tdata.value)
                for i in range(DATA_BYTES):
                    if (keep >> i) & 1:
                        cur.append((data >> (8 * i)) & 0xFF)
                if int(dut.m_tlast.value):
                    got.append(bytes(cur))
                    cur.clear()

    cocotb.start_soon(monitor())

    # 1/2: both feeds offer the expected sequence -> prefer A.
    await send_frame(dut, "a", 1, 1, frame(1))
    await send_frame(dut, "b", 1, 1, frame(1))
    await wait_frames(dut, got, 1)

    await send_frame(dut, "a", 2, 1, frame(2))
    await send_frame(dut, "b", 2, 1, frame(2))
    await wait_frames(dut, got, 2)

    # 3: expected 3; A is ahead (4), B has the expected frame -> pick B.
    await send_frame(dut, "a", 4, 1, frame(4))
    await send_frame(dut, "b", 3, 1, frame(3))
    await wait_frames(dut, got, 3)

    # 4: expected 4; A's buffered 4 wins the tie against B's 4.
    await send_frame(dut, "b", 4, 1, frame(4))
    await wait_frames(dut, got, 4)

    # 5: expected 5, both feeds jump to 7 -> gap, lower (A) selected.
    await send_frame(dut, "a", 7, 1, frame(7))
    await send_frame(dut, "b", 7, 1, frame(7))
    await wait_frames(dut, got, 5)

    # 6: only B has the expected frame -> the redundancy window expires, B wins.
    await send_frame(dut, "b", 8, 1, frame(8))
    await wait_frames(dut, got, 6)

    markers = [f[0] for f in got]
    assert markers == [1, 2, 3, 4, 7, 8], f"selected sequence {markers}"
    for seq, f in zip(markers, got):
        assert f == frame(seq), f"frame {seq} bytes differ"
    assert int(dut.gaps.value) == 1, f"gaps {int(dut.gaps.value)}"
    assert int(dut.expected_seq.value) == 9, f"expected {int(dut.expected_seq.value)}"
    dut._log.info(
        f"Arbiter: {len(got)} frames selected {markers}, gaps=1, "
        f"drop_a={int(dut.dropped_a.value)} drop_b={int(dut.dropped_b.value)} PASS")

@cocotb.test()
async def test_recovery_mode(dut):
    """Gap -> retransmit request -> replay -> timeout abandon."""
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.initial_seq.value = 1
    dut.recovery_en.value = 1
    dut.a_tvalid.value = 0
    dut.a_tlast.value = 0
    dut.a_tdata.value = 0
    dut.a_tkeep.value = 0
    dut.a_seq.value = 0
    dut.a_count.value = 0
    dut.b_tvalid.value = 0
    dut.b_tlast.value = 0
    dut.b_tdata.value = 0
    dut.b_tkeep.value = 0
    dut.b_seq.value = 0
    dut.b_count.value = 0
    dut.m_tready.value = 1
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    got = []
    cur = bytearray()
    abandons = 0

    async def monitor():
        nonlocal abandons
        while True:
            await FallingEdge(dut.clk)
            if int(dut.abandon.value):
                abandons += 1
            if int(dut.m_tvalid.value) and int(dut.m_tready.value):
                keep = int(dut.m_tkeep.value)
                data = int(dut.m_tdata.value)
                for i in range(DATA_BYTES):
                    if (keep >> i) & 1:
                        cur.append((data >> (8 * i)) & 0xFF)
                if int(dut.m_tlast.value):
                    got.append(bytes(cur))
                    cur.clear()

    cocotb.start_soon(monitor())

    await send_frame(dut, "a", 1, 1, frame(1))
    await send_frame(dut, "b", 1, 1, frame(1))
    await wait_frames(dut, got, 1)

    # Gap: expected 2, both feeds at 3 -> request 2, no output.
    await send_frame(dut, "a", 3, 1, frame(3))
    await send_frame(dut, "b", 3, 1, frame(3))
    for _ in range(4):
        await RisingEdge(dut.clk)
    assert int(dut.req_valid.value) == 1, "no retransmit request"
    assert int(dut.req_seq.value) == 2, f"req_seq {int(dut.req_seq.value)}"
    assert int(dut.req_count.value) == 1, f"req_count {int(dut.req_count.value)}"
    assert len(got) == 1, f"gap frame leaked: {len(got)}"

    # Replay closes the gap, then the replayed frame 3 is accepted.
    await send_frame(dut, "a", 2, 1, frame(2))
    await send_frame(dut, "b", 2, 1, frame(2))
    await wait_frames(dut, got, 2)
    assert int(dut.req_valid.value) == 0, "request not cleared"
    await send_frame(dut, "a", 3, 1, frame(3))
    await send_frame(dut, "b", 3, 1, frame(3))
    await wait_frames(dut, got, 3)

    # Timeout: expected 4, both at 6 -> request, then abandon and force-accept.
    await send_frame(dut, "a", 6, 1, frame(6))
    await send_frame(dut, "b", 6, 1, frame(6))
    for _ in range(400):
        await RisingEdge(dut.clk)
    assert abandons == 1, f"abandons {abandons}"
    assert int(dut.abandoned.value) == 1, "abandoned counter"
    assert int(dut.requests.value) == 2, f"requests {int(dut.requests.value)}"

    await send_frame(dut, "a", 6, 1, frame(6))
    await send_frame(dut, "b", 6, 1, frame(6))
    await wait_frames(dut, got, 4)
    markers = [f[0] for f in got]
    assert markers == [1, 2, 3, 6], f"markers {markers}"
    dut._log.info(f"Recovery mode: markers {markers}, requests=2, abandon=1 PASS")

