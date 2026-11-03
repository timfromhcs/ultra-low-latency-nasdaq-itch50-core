# =============================================================================
# File: tb/test_ab_system.py
# Description: Two MoldUDP64 Ethernet feeds -> arbiter -> one ITCH stream.
# =============================================================================
import os
import sys
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import itch_model as m
from mold_vectors import eth_mold_frame

DATA_BYTES = 16


async def send_eth(dut, feed, frame):
    p = "a_" if feed == "a" else "b_"
    tdata = getattr(dut, p + "tdata")
    tkeep = getattr(dut, p + "tkeep")
    tvalid = getattr(dut, p + "tvalid")
    tlast = getattr(dut, p + "tlast")
    tready = getattr(dut, p + "tready")
    off = 0
    while off < len(frame):
        chunk = frame[off:off + DATA_BYTES]
        off += len(chunk)
        pad = chunk + b"\x00" * (DATA_BYTES - len(chunk))
        await FallingEdge(dut.clk)
        tdata.value = int.from_bytes(pad, "little")
        tkeep.value = (1 << len(chunk)) - 1
        tvalid.value = 1
        tlast.value = 1 if off >= len(frame) else 0
        guard = 0
        while int(tready.value) == 0:
            await FallingEdge(dut.clk)
            guard += 1
            if guard > 20000:
                raise TimeoutError("pipeline backpressure stuck")
        await RisingEdge(dut.clk)
    tvalid.value = 0
    tlast.value = 0
    await RisingEdge(dut.clk)


async def feed_pair(dut, fa, fb):
    tasks = []
    if fa is not None:
        tasks.append(cocotb.start_soon(send_eth(dut, "a", fa)))
    if fb is not None:
        tasks.append(cocotb.start_soon(send_eth(dut, "b", fb)))
    for t in tasks:
        await t


@cocotb.test()
async def test_ab_system(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.cfg_dst_ip.value = int.from_bytes(bytes([233, 54, 12, 111]), "big")
    dut.cfg_ip_mask.value = 0xFFFFFFFF
    dut.cfg_udp_port.value = 26400
    dut.cfg_check_ip.value = 1
    dut.cfg_check_port.value = 1
    dut.cfg_initial_seq.value = 1
    dut.cfg_recovery_en.value = 0
    for p in ("a_", "b_"):
        getattr(dut, p + "tvalid").value = 0
        getattr(dut, p + "tlast").value = 0
        getattr(dut, p + "tdata").value = 0
        getattr(dut, p + "tkeep").value = 0
    dut.m_tready.value = 1
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    rng = random.Random(31)
    msgs = [m.build_message(rng, list(m.LENGTHS)[i % 22], i) for i in range(10)]
    m0, m1, m2, m3, m4 = msgs[0:2], msgs[2:4], msgs[4:6], msgs[6:8], msgs[8:10]

    got = []
    cur = bytearray()
    gaps = 0

    async def monitor():
        nonlocal gaps
        while True:
            await FallingEdge(dut.clk)
            if int(dut.gap.value):
                gaps += 1
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

    # Both feeds carry the same frames; A is preferred on ties.
    await feed_pair(dut, eth_mold_frame(1, m0), eth_mold_frame(1, m0))
    # Expected 3: A is at 3, B lags at 2 -> A.
    await feed_pair(dut, eth_mold_frame(3, m1), eth_mold_frame(2, m1))
    # Expected 5: both at 5 -> A.
    await feed_pair(dut, eth_mold_frame(5, m2), eth_mold_frame(5, m2))
    # Expected 7: both jump to 10 -> gap, A wins the tie.
    await feed_pair(dut, eth_mold_frame(10, m3), eth_mold_frame(10, m3))
    # Expected 12: only B has it -> B after the redundancy window.
    await feed_pair(dut, None, eth_mold_frame(12, m4))

    for _ in range(20000):
        if len(got) >= 5:
            break
        await RisingEdge(dut.clk)

    assert len(got) == 5, f"frames out {len(got)}"
    stream = b"".join(got)
    expected = b"".join(msgs[0:10])
    assert len(stream) == len(expected), f"bytes {len(stream)} != {len(expected)}"
    recs = m.parse_stream(stream)
    exp = m.parse_stream(expected)
    assert len(recs) == len(exp), f"records {len(recs)} != {len(exp)}"
    for i, (a, b) in enumerate(zip(recs, exp)):
        assert a.pack()[:76] == b.pack()[:76], f"record {i} mismatch"
    assert gaps == 1, f"gaps {gaps}"
    assert int(dut.expected_seq.value) == 14, f"expected_seq {int(dut.expected_seq.value)}"
    dut._log.info(f"A/B system: {len(got)} frames, {len(recs)} records, gaps=1 PASS")
