# =============================================================================
# File: tb/test_metrics.py
# Description: itch_metrics counters and inter-message gap histogram.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))


async def send_msg(dut, idle_cycles=0, length=20):
    for _ in range(idle_cycles):
        await RisingEdge(dut.clk)
    dut.msg_valid.value = 1
    dut.msg_len.value = length
    await RisingEdge(dut.clk)
    dut.msg_valid.value = 0


@cocotb.test()
async def test_metrics(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.msg_valid.value = 0
    dut.msg_len.value = 0
    dut.gap_pulse.value = 0
    dut.drop_pulse.value = 0
    dut.occupancy.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Histogram: the first message is one idle cycle after reset (bin1), then a
    # back-to-back pair (bin0), then one message per remaining bin.
    await send_msg(dut, 0)          # bin1 (since was 1 after the reset edge)
    await send_msg(dut, 0)          # bin0 (back-to-back)
    await send_msg(dut, 1)          # bin1
    await send_msg(dut, 2)          # bin2
    await send_msg(dut, 3)          # bin3
    await send_msg(dut, 5)          # bin4
    await send_msg(dut, 10)         # bin5
    await send_msg(dut, 20)         # bin6
    await send_msg(dut, 40)         # bin7

    # Gap / drop pulses and occupancy peaks.
    dut.gap_pulse.value = 1
    await RisingEdge(dut.clk)
    dut.gap_pulse.value = 0
    await RisingEdge(dut.clk)
    dut.gap_pulse.value = 1
    await RisingEdge(dut.clk)
    dut.gap_pulse.value = 0
    dut.drop_pulse.value = 1
    await RisingEdge(dut.clk)
    dut.drop_pulse.value = 0
    for v in (5, 9, 3):
        dut.occupancy.value = v
        await RisingEdge(dut.clk)

    # Let the free-running cycle counter pass 100.
    for _ in range(20):
        await RisingEdge(dut.clk)

    total = int(dut.msg_count.value)
    assert total == 9, f"msg_count {total}"
    assert int(dut.byte_count.value) == 9 * 20, f"byte_count {int(dut.byte_count.value)}"
    assert int(dut.gap_count.value) == 2, f"gap {int(dut.gap_count.value)}"
    assert int(dut.drop_count.value) == 1, f"drop {int(dut.drop_count.value)}"
    assert int(dut.occupancy_max.value) == 9, f"occ_max {int(dut.occupancy_max.value)}"
    assert int(dut.cycle_count.value) > 100, "cycle counter not running"

    hist = [int(getattr(dut, f"hist{i}").value) for i in range(8)]
    expected = [1, 2, 1, 1, 1, 1, 1, 1]
    assert hist == expected, f"hist {hist} != {expected}"
    dut._log.info(f"Metrics: {total} messages, hist={hist}, occ_max=9 PASS")
