# =============================================================================
# File: tb/test_wishbone.py
# Description: itch_wishbone_wrap: Wishbone reads of the host register file.
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


async def wb_read(dut, addr):
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value = 0
    dut.wb_adr.value = addr
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert int(dut.wb_ack.value) == 1, f"no ack for read {addr}"
    data = int(dut.wb_dat_r.value)
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    await RisingEdge(dut.clk)
    return data


async def wb_write(dut, addr, data):
    dut.wb_cyc.value = 1
    dut.wb_stb.value = 1
    dut.wb_we.value = 1
    dut.wb_adr.value = addr
    dut.wb_dat_w.value = data
    dut.wb_sel.value = 0xF
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    ack = int(dut.wb_ack.value)
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value = 0
    await RisingEdge(dut.clk)
    return ack


@cocotb.test()
async def test_wishbone(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.wb_cyc.value = 0
    dut.wb_stb.value = 0
    dut.wb_we.value = 0
    dut.wb_adr.value = 0
    dut.wb_dat_w.value = 0
    dut.wb_sel.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    ref = 0x0BADF00D11223344
    await send_bytes(dut, msg_add(7, ref, 250, 999, 1))
    await send_bytes(dut, msg_cancel(7, ref, 50, 2))
    for _ in range(200):
        if (await wb_read(dut, 10)) >= 2:
            break

    assert await wb_read(dut, 0) == 2, "msg_count"
    word2 = await wb_read(dut, 2)
    assert (word2 >> 24) & 0xFF == ord("X"), f"type {word2:#x}"
    assert word2 & 0xFFFF == 7, f"locate {word2:#x}"
    assert await wb_read(dut, 4) == 50, "shares"
    assert await wb_read(dut, 6) == (ref & 0xFFFFFFFF), "ref low"
    assert await wb_read(dut, 7) == (ref >> 32), "ref high"

    # Writes are acknowledged but ignored.
    assert await wb_write(dut, 0, 0xDEADBEEF) == 1, "write ack"
    assert await wb_read(dut, 0) == 2, "write must not change msg_count"

    dut._log.info("Wishbone: 2 messages, type X, locate 7, shares 50, ref round-trip PASS")
