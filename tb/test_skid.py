# =============================================================================
# File: tb/test_skid.py
# Description: Random AXI4-Stream skid-buffer regression.
# =============================================================================
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

DATA_BYTES = 16


@cocotb.test()
async def test_skid_no_loss_and_stable_output(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_tvalid.value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.s_tlast.value = 0
    dut.m_tready.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    rng = random.Random(7)
    expected = []
    got = []
    sent = 0

    for cycle in range(2000):
        # Drive a new beat sometimes, but only if the DUT is ready.
        if sent < 200 and rng.random() < 0.55:
            data = bytes([(sent + i) & 0xFF for i in range(DATA_BYTES)])
            dut.s_tdata.value = int.from_bytes(data, "little")
            dut.s_tkeep.value = 0xFFFF
            dut.s_tlast.value = 1 if (sent % 7 == 6) else 0
            dut.s_tvalid.value = 1
        else:
            dut.s_tvalid.value = 0
            dut.s_tlast.value = 0

        # Random downstream back-pressure.
        dut.m_tready.value = 1 if rng.random() < 0.55 else 0
        await RisingEdge(dut.clk)

        # Sample handshakes after the edge (registered outputs).
        if int(dut.s_tvalid.value) and int(dut.s_tready.value):
            expected.append((int(dut.s_tdata.value), int(dut.s_tkeep.value), int(dut.s_tlast.value)))
            sent += 1
        if int(dut.m_tvalid.value) and int(dut.m_tready.value):
            got.append((int(dut.m_tdata.value), int(dut.m_tkeep.value), int(dut.m_tlast.value)))
        assert int(dut.occupancy.value) <= 2, "occupancy overflow"

    # Drain
    dut.s_tvalid.value = 0
    dut.m_tready.value = 1
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.m_tvalid.value):
            got.append((int(dut.m_tdata.value), int(dut.m_tkeep.value), int(dut.m_tlast.value)))

    assert len(got) == len(expected), f"{len(got)} != {len(expected)}"
    for i, (a, b) in enumerate(zip(expected, got)):
        assert a == b, f"beat {i} mismatch: {a} != {b}"
    dut._log.info(f"SKID: {len(got)} beats, no loss, PASS")
