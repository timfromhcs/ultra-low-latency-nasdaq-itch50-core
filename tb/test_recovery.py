# =============================================================================
# File: tb/test_recovery.py
# Description: Mold sequence recovery: gap request, replay recovery, timeout
#              abandon and duplicate rejection.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
TIMEOUT = 16


async def send_frame(dut, seq, count):
    dut.frame_valid.value = 1
    dut.frame_seq.value = seq
    dut.frame_count.value = count
    await RisingEdge(dut.clk)
    dut.frame_valid.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_sequence_recovery(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.initial_seq.value = 1
    dut.frame_valid.value = 0
    dut.frame_seq.value = 0
    dut.frame_count.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    accepts = []
    abandons = 0

    async def monitor():
        nonlocal abandons
        while True:
            await RisingEdge(dut.clk)
            if int(dut.accept.value):
                accepts.append(int(dut.expected.value))
            if int(dut.abandon.value):
                abandons += 1

    cocotb.start_soon(monitor())

    # In-order frame.
    await send_frame(dut, 1, 2)
    assert int(dut.expected.value) == 3, f"expected {int(dut.expected.value)}"
    assert len(accepts) == 1, f"accepts {accepts}"

    # Forward gap: request the missing range [3, 5).
    await send_frame(dut, 5, 2)
    assert int(dut.req_valid.value) == 1, "no retransmit request"
    assert int(dut.req_seq.value) == 3, f"req_seq {int(dut.req_seq.value)}"
    assert int(dut.req_count.value) == 2, f"req_count {int(dut.req_count.value)}"
    assert int(dut.gaps.value) == 1, f"gaps {int(dut.gaps.value)}"

    # Replay closes the gap.
    await send_frame(dut, 3, 2)
    assert int(dut.expected.value) == 5, f"expected {int(dut.expected.value)}"
    assert int(dut.recovered.value) == 1, f"recovered {int(dut.recovered.value)}"
    assert int(dut.req_valid.value) == 0, "request not cleared"

    # The originally dropped frame now arrives in order.
    await send_frame(dut, 5, 2)
    assert int(dut.expected.value) == 7, f"expected {int(dut.expected.value)}"

    # Forward gap that is never replayed: abandon after TIMEOUT.
    await send_frame(dut, 9, 1)
    assert int(dut.req_valid.value) == 1, "no request for second gap"
    assert int(dut.req_seq.value) == 7, f"req_seq {int(dut.req_seq.value)}"
    for _ in range(TIMEOUT + 20):
        await RisingEdge(dut.clk)
    assert abandons == 1, f"abandons {abandons}"
    assert int(dut.abandoned.value) == 1, f"abandoned {int(dut.abandoned.value)}"
    assert int(dut.expected.value) == 9, f"resync expected {int(dut.expected.value)}"

    # A stale frame is a duplicate and must not be accepted.
    await send_frame(dut, 5, 2)
    assert int(dut.duplicates.value) == 1, f"dups {int(dut.duplicates.value)}"

    # Resynchronised stream continues.
    await send_frame(dut, 9, 1)
    assert int(dut.expected.value) == 10, f"expected {int(dut.expected.value)}"
    assert len(accepts) == 4, f"accepts {accepts}"

    dut._log.info(
        f"Recovery: 4 accepts, 2 gaps, 1 recovered, 1 abandoned, 1 duplicate PASS")
