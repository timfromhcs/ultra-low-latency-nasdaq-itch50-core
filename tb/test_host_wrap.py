# =============================================================================
# File: tb/test_host_wrap.py
# Description: itch_host_wrap: 128-bit ingress -> narrow host register port.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

DATA_BYTES = 16
STOCK = b"AAPL    "


def hdr(t, locate, idx):
    return (bytes([ord(t)]) + locate.to_bytes(2, "big") + (idx & 0xFFFF).to_bytes(2, "big")
            + (34_200_000_000_000 + idx).to_bytes(6, "big"))


def msg_add(locate, ref, shares, price, idx):
    return (hdr("A", locate, idx) + ref.to_bytes(8, "big") + b"B"
            + shares.to_bytes(4, "big") + STOCK + price.to_bytes(4, "big"))


def msg_cancel(locate, ref, shares, idx):
    return hdr("X", locate, idx) + ref.to_bytes(8, "big") + shares.to_bytes(4, "big")


async def send_bytes(dut, data):
    off = 0
    while off < len(data):
        chunk = data[off:off + DATA_BYTES]
        off += len(chunk)
        pad = chunk + b"\x00" * (DATA_BYTES - len(chunk))
        dut.s_axis_tdata.value = int.from_bytes(pad, "little")
        dut.s_axis_tkeep.value = (1 << len(chunk)) - 1
        dut.s_axis_tvalid.value = 1
        dut.s_axis_tlast.value = 1 if off >= len(data) else 0
        await RisingEdge(dut.clk)
        guard = 0
        while int(dut.s_axis_tready.value) == 0:
            await RisingEdge(dut.clk)
            guard += 1
            if guard > 20000:
                raise TimeoutError("parser backpressure stuck")
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    await RisingEdge(dut.clk)


async def read(dut, addr):
    dut.host_addr.value = addr
    await Timer(1, unit="ns")
    return int(dut.host_rdata.value)


@cocotb.test()
async def test_host_wrap(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.host_addr.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    ref = 0x1122334455667788
    await send_bytes(dut, msg_add(3, ref, 500, 12345, 1))
    await send_bytes(dut, msg_cancel(3, ref, 100, 2))

    for _ in range(200):
        if int(dut.updates.value) >= 2:
            break
        await RisingEdge(dut.clk)
    assert int(dut.updates.value) == 2, f"updates {int(dut.updates.value)}"

    assert await read(dut, 0) == 2, "msg_count"
    assert await read(dut, 1) == 0, "corrupt_count"
    word2 = await read(dut, 2)
    assert (word2 >> 24) & 0xFF == ord("X"), f"type {word2:#x}"
    assert word2 & 0xFFFF == 3, f"locate {word2:#x}"
    assert (await read(dut, 4)) == 100, "shares low"
    assert (await read(dut, 5)) == 0, "shares high"
    assert (await read(dut, 6)) == (ref & 0xFFFFFFFF), "ref low"
    assert (await read(dut, 7)) == (ref >> 32), "ref high"
    flags = await read(dut, 8)
    assert flags & 1 == 1, "last_valid"
    assert (flags >> 1) & 1 == 0, "unexpected corrupt"
    assert await read(dut, 10) == 2, "updates register"
    assert await read(dut, 31) == 0, "unmapped read must be zero"

    dut._log.info("Host wrap: 2 messages, type X, locate 3, shares 100, ref rounded-trip PASS")
