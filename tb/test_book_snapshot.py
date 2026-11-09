# =============================================================================
# File: tb/test_book_snapshot.py
# Description: Integration: parser + top-of-book + per-locate snapshot. The
#              snapshot must mirror the last BBO event for each locate.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

DATA_BYTES = 16
STOCK = b"AAPL    "


def hdr(t, locate, idx):
    return (bytes([ord(t)]) + locate.to_bytes(2, "big") + (idx & 0xFFFF).to_bytes(2, "big")
            + (34_200_000_000_000 + idx).to_bytes(6, "big"))


def msg_add(locate, ref, side, shares, price, idx):
    return (hdr("A", locate, idx) + ref.to_bytes(8, "big") + side
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


async def read_snapshot(dut, locate):
    dut.rd_valid.value = 1
    dut.rd_locate.value = locate
    await RisingEdge(dut.clk)
    dut.rd_valid.value = 0
    await FallingEdge(dut.clk)
    return {name: int(getattr(dut, f"snap_{name}").value) for name in (
        "valid", "locate", "hit", "bid_price", "bid_shares", "ask_price", "ask_shares",
        "last_price", "last_shares", "volume",
        "bid_p0", "bid_p1", "bid_p2", "bid_p3", "bid_s0", "bid_s1", "bid_s2", "bid_s3",
        "ask_p0", "ask_p1", "ask_p2", "ask_p3", "ask_s0", "ask_s1", "ask_s2", "ask_s3",
        "updates")}


@cocotb.test()
async def test_book_snapshot(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.rd_valid.value = 0
    dut.rd_locate.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    for _ in range(2000):
        if int(dut.ready.value) == 1:
            break
        await RisingEdge(dut.clk)
    assert int(dut.ready.value) == 1, "book never became ready"

    last = {}

    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            if int(dut.u_book.bbo_valid.value):
                await Timer(1, unit="ns")
                loc = int(dut.u_book.bbo_locate.value)
                last[loc] = {name: int(getattr(dut.u_book, f"bbo_{name}").value) for name in (
                    "bid_price", "bid_shares", "ask_price", "ask_shares",
                    "last_price", "last_shares", "volume",
                    "bid_p0", "bid_p1", "bid_p2", "bid_p3", "bid_s0", "bid_s1", "bid_s2", "bid_s3",
                    "ask_p0", "ask_p1", "ask_p2", "ask_p3", "ask_s0", "ask_s1", "ask_s2", "ask_s3")}

    cocotb.start_soon(monitor())

    ref1 = 0x1111222233334444
    ref2 = 0x5555666677778888
    await send_bytes(dut, msg_add(1, ref1, b"B", 100, 1000, 1))
    await send_bytes(dut, msg_add(2, ref2, b"B", 200, 2000, 2))
    await send_bytes(dut, msg_cancel(1, ref1, 40, 3))
    for _ in range(300):
        if len(last) >= 2:
            break
        await RisingEdge(dut.clk)
    for _ in range(20):
        await RisingEdge(dut.clk)

    assert 1 in last and 2 in last, f"no BBO for both locates: {sorted(last)}"

    s1 = await read_snapshot(dut, 1)
    assert s1["valid"] == 1 and s1["hit"] == 1, s1
    assert s1["locate"] == 1, s1
    for name in ("bid_price", "bid_shares", "ask_price", "ask_shares", "last_price",
                 "last_shares", "volume", "bid_p0", "bid_p1", "bid_p2", "bid_p3",
                 "bid_s0", "bid_s1", "bid_s2", "bid_s3", "ask_p0", "ask_p1", "ask_p2",
                 "ask_p3", "ask_s0", "ask_s1", "ask_s2", "ask_s3"):
        assert s1[name] == last[1][name], f"locate 1 {name}: snap {s1[name]} bbo {last[1][name]}"

    s2 = await read_snapshot(dut, 2)
    assert s2["hit"] == 1 and s2["bid_price"] == last[2]["bid_price"], s2
    assert s2["volume"] == last[2]["volume"], s2

    miss = await read_snapshot(dut, 3)
    assert miss["valid"] == 1 and miss["hit"] == 0, miss
    assert miss["bid_price"] == 0 and miss["volume"] == 0, miss

    dut._log.info("Book snapshot: locate 1/2 mirror the last BBO, locate 3 is a miss PASS")
