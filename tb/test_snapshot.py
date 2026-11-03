# =============================================================================
# File: tb/test_snapshot.py
# Description: itch_book_snapshot per-locate host read port.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))


async def update(dut, locate, bid, bid_sz, ask, ask_sz, last, last_sz, vol, base):
    dut.upd_valid.value = 1
    dut.upd_locate.value = locate
    dut.upd_bid_price.value = bid
    dut.upd_bid_shares.value = bid_sz
    dut.upd_ask_price.value = ask
    dut.upd_ask_shares.value = ask_sz
    dut.upd_last_price.value = last
    dut.upd_last_shares.value = last_sz
    dut.upd_volume.value = vol
    dut.upd_bid_p0.value = base + 0
    dut.upd_bid_s0.value = 10 + base
    dut.upd_bid_p1.value = base + 1
    dut.upd_bid_s1.value = 20 + base
    dut.upd_bid_p2.value = base + 2
    dut.upd_bid_s2.value = 30 + base
    dut.upd_bid_p3.value = base + 3
    dut.upd_bid_s3.value = 40 + base
    dut.upd_ask_p0.value = base + 10
    dut.upd_ask_s0.value = 50 + base
    dut.upd_ask_p1.value = base + 11
    dut.upd_ask_s1.value = 60 + base
    dut.upd_ask_p2.value = base + 12
    dut.upd_ask_s2.value = 70 + base
    dut.upd_ask_p3.value = base + 13
    dut.upd_ask_s3.value = 80 + base
    await RisingEdge(dut.clk)
    dut.upd_valid.value = 0


async def read(dut, locate):
    dut.rd_valid.value = 1
    dut.rd_locate.value = locate
    await RisingEdge(dut.clk)
    dut.rd_valid.value = 0
    await FallingEdge(dut.clk)
    assert int(dut.snap_valid.value) == 1, "snap_valid not asserted"
    return {name: int(getattr(dut, f"snap_{name}").value) for name in (
        "locate", "hit", "bid_price", "bid_shares", "ask_price", "ask_shares",
        "last_price", "last_shares", "volume",
        "bid_p0", "bid_p1", "bid_p2", "bid_p3",
        "bid_s0", "bid_s1", "bid_s2", "bid_s3",
        "ask_p0", "ask_p1", "ask_p2", "ask_p3",
        "ask_s0", "ask_s1", "ask_s2", "ask_s3")}


@cocotb.test()
async def test_snapshot(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.upd_valid.value = 0
    for name in ("upd_locate", "upd_bid_price", "upd_bid_shares", "upd_ask_price",
                 "upd_ask_shares", "upd_last_price", "upd_last_shares", "upd_volume",
                 "upd_bid_p0", "upd_bid_p1", "upd_bid_p2", "upd_bid_p3",
                 "upd_bid_s0", "upd_bid_s1", "upd_bid_s2", "upd_bid_s3",
                 "upd_ask_p0", "upd_ask_p1", "upd_ask_p2", "upd_ask_p3",
                 "upd_ask_s0", "upd_ask_s1", "upd_ask_s2", "upd_ask_s3"):
        getattr(dut, name).value = 0
    dut.rd_valid.value = 0
    dut.rd_locate.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Not-yet-updated locate reads as a miss.
    miss = await read(dut, 3)
    assert miss["hit"] == 0, f"unexpected hit {miss}"
    assert miss["bid_price"] == 0 and miss["volume"] == 0

    await update(dut, 1, 100, 500, 101, 600, 100, 10, 1000, 1)
    await update(dut, 2, 200, 700, 201, 800, 200, 20, 2000, 100)

    s1 = await read(dut, 1)
    assert s1["locate"] == 1 and s1["hit"] == 1, s1
    assert s1["bid_price"] == 100 and s1["bid_shares"] == 500, s1
    assert s1["ask_price"] == 101 and s1["ask_shares"] == 600, s1
    assert s1["last_price"] == 100 and s1["last_shares"] == 10 and s1["volume"] == 1000, s1
    assert [s1[f"bid_p{i}"] for i in range(4)] == [1, 2, 3, 4], s1
    assert [s1[f"bid_s{i}"] for i in range(4)] == [11, 21, 31, 41], s1
    assert [s1[f"ask_p{i}"] for i in range(4)] == [11, 12, 13, 14], s1
    assert [s1[f"ask_s{i}"] for i in range(4)] == [51, 61, 71, 81], s1

    # Another locate is independent.
    s2 = await read(dut, 2)
    assert s2["locate"] == 2 and s2["bid_price"] == 200 and s2["volume"] == 2000, s2
    assert s2["bid_p0"] == 100, s2

    # Snapshot is stable across unrelated updates until the next read.
    await update(dut, 5, 999, 9, 1000, 9, 999, 9, 9, 7)
    held = {name: int(getattr(dut, f"snap_{name}").value) for name in ("locate", "bid_price", "volume")}
    assert held == {"locate": 2, "bid_price": 200, "volume": 2000}, f"snapshot changed without read: {held}"

    # A later update to locate 2 is visible on the next read.
    await update(dut, 2, 250, 750, 251, 850, 250, 25, 2500, 200)
    s2b = await read(dut, 2)
    assert s2b["bid_price"] == 250 and s2b["bid_p3"] == 203, s2b

    assert int(dut.updates.value) == 4, f"updates {int(dut.updates.value)}"
    dut._log.info("Snapshot: locate 1/2 read back, miss on 3, updates=4 PASS")
