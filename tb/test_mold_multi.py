# =============================================================================
# File: tb/test_mold_multi.py
# Description: Five MoldUDP64 frames back-to-back (no idle wait): four valid
#              frames, one sequence gap, one dropped-port frame. Proves the
#              multi-frame handoff (R1) end to end.
# =============================================================================
import os
import sys
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import itch_model as m
from mold_vectors import eth_mold_frame

DATA_BYTES = 16


async def send_frame(dut, frame: bytes):
    off = 0
    while off < len(frame):
        chunk = frame[off:off + DATA_BYTES]
        off += len(chunk)
        pad = chunk + b"\x00" * (DATA_BYTES - len(chunk))
        dut.s_axis_tdata.value = int.from_bytes(pad, "little")
        dut.s_axis_tkeep.value = (1 << len(chunk)) - 1
        dut.s_axis_tvalid.value = 1
        dut.s_axis_tlast.value = 1 if off >= len(frame) else 0
        await RisingEdge(dut.clk)
        guard = 0
        while dut.s_axis_tready.value == 0:
            await RisingEdge(dut.clk)
            guard += 1
            if guard > 20000:
                raise TimeoutError("front-end backpressure stuck")
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_multi_frame_back_to_back(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    dut.s_axis_tdata.value = 0
    dut.m_axis_tready.value = 1
    dut.cfg_dst_ip.value = int.from_bytes(bytes([233, 54, 12, 111]), "big")
    dut.cfg_ip_mask.value = 0xFFFFFFFF
    dut.cfg_udp_port.value = 26400
    dut.cfg_check_ip.value = 1
    dut.cfg_check_port.value = 1
    dut.cfg_initial_seq.value = 1
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    rng = random.Random(21)
    msgs = [m.build_message(rng, list(m.LENGTHS)[i % 22], i) for i in range(64)]
    received = bytearray()
    gaps = 0
    drops = 0
    frames_done = 0

    async def monitor():
        nonlocal gaps, drops, frames_done
        while True:
            await RisingEdge(dut.clk)
            if int(dut.mold_gap.value):
                gaps += 1
            if int(dut.mold_frame_drop.value):
                drops += 1
            if int(dut.m_axis_tvalid.value):
                keep = int(dut.m_axis_tkeep.value)
                data = int(dut.m_axis_tdata.value)
                for i in range(DATA_BYTES):
                    if (keep >> i) & 1:
                        received.append((data >> (8 * i)) & 0xFF)
                if int(dut.m_axis_tlast.value):
                    frames_done += 1

    cocotb.start_soon(monitor())

    frames = [
        eth_mold_frame(1, msgs[0:8]),                    # ok, expected becomes 9
        eth_mold_frame(17, msgs[8:16]),                  # gap: expected 9
        eth_mold_frame(25, msgs[16:24]),                 # ok
        eth_mold_frame(33, msgs[24:28], dst_port=9999),  # dropped port
        eth_mold_frame(33, msgs[28:32]),                 # ok: expected still 33
    ]
    for idx, f in enumerate(frames):
        await send_frame(dut, f)
        dut._log.info(f"frame {idx} sent ({len(f)} B)")

    # Drain
    for _ in range(800):
        await RisingEdge(dut.clk)

    expected = b"".join(msgs[0:24] + msgs[28:32])
    assert len(received) == len(expected), f"len {len(received)} != {len(expected)}"
    assert frames_done == 4, f"frame ends {frames_done}"
    assert gaps == 1, f"gap pulses {gaps}"
    assert drops == 1, f"drop pulses {drops}"
    recs = m.parse_stream(bytes(received))
    exp = m.parse_stream(expected)
    assert len(recs) == len(exp), f"records {len(recs)} != {len(exp)}"
    for i, (a, b) in enumerate(zip(recs, exp)):
        assert a.pack()[:76] == b.pack()[:76], f"record {i} mismatch"
    dut._log.info(f"Multi-frame: {len(recs)} records, gaps={gaps}, drops={drops} PASS")
