# =============================================================================
# File: tb/test_mold.py
# Description: Cocotb regression for rtl/moldudp64_frontend.sv.
#   * validates Ethernet/IP/UDP/Mold filtering and payload repacking
#   * validates sequence-gap detection
#   * validates port/IP filtering and drop accounting
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import itch_model as m
from mold_vectors import eth_mold_frame

DATA_BYTES = 16


def messages_for_test(count=64):
    rng = __import__("random").Random(7)
    types = list(m.LENGTHS)
    msgs = []
    for i in range(count):
        t = types[i % len(types)]
        msgs.append(m.build_message(rng, t, i))
    return msgs


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
        while dut.s_axis_tready.value == 0:
            await RisingEdge(dut.clk)
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    await RisingEdge(dut.clk)


def collect_byte(dut):
    keep = int(dut.m_axis_tkeep.value)
    data = int(dut.m_axis_tdata.value)
    out = bytearray()
    for i in range(DATA_BYTES):
        if (keep >> i) & 1:
            out.append((data >> (8 * i)) & 0xFF)
    return bytes(out)


@cocotb.test()
async def test_mold_filter_repack_and_gap(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    dut.s_axis_tdata.value = 0
    dut.frame_busy.value = 0
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

    msgs = messages_for_test(64)
    payload = bytearray()
    received = bytearray()
    gaps = 0
    drops = 0

    async def monitor():
        nonlocal received, gaps, drops
        while True:
            await RisingEdge(dut.clk)
            if int(dut.mold_gap.value):
                gaps += 1
            if int(dut.mold_frame_drop.value):
                drops += 1
            if int(dut.m_axis_tvalid.value):
                received.extend(collect_byte(dut))

    cocotb.start_soon(monitor())

    # MoldUDP64 sequence = first message sequence, and advances by msg_count.
    # Frame 1 (8 msgs, seq 1) -> next expected 9; frame 2 starts at 17 => gap.
    frames = [
        eth_mold_frame(1, msgs[0:8]),
        eth_mold_frame(17, msgs[8:16]),
        eth_mold_frame(25, msgs[16:24]),
    ]
    for f in frames:
        payload.extend(f)
        await send_frame(dut, f)

    # Invalid port frame must be dropped and must not advance the sequence.
    bad = eth_mold_frame(33, msgs[24:28], dst_port=9999)
    await send_frame(dut, bad)

    # Valid frame after the drop.
    good = eth_mold_frame(33, msgs[28:32])
    await send_frame(dut, good)

    for _ in range(200):
        await RisingEdge(dut.clk)

    # The front-end deliberately exports the raw Mold payload (length prefixes
    # included); the depacketizer strips them. Compare that contract exactly.
    def mold_payload(items):
        return b"".join(len(x).to_bytes(2, "big") + x for x in items)

    expected = mold_payload(msgs[0:24] + msgs[28:32])
    assert gaps == 1, f"expected 1 gap pulse, got {gaps}"
    assert drops == 1, f"expected 1 dropped frame, got {drops}"
    assert len(received) == len(expected), f"payload length {len(received)} != {len(expected)}"
    assert bytes(received) == expected, "front-end raw Mold payload mismatch"
    dut._log.info(f"Mold front-end: {len(expected)} payload bytes, gaps={gaps}, drops={drops} PASS")
