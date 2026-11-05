# =============================================================================
# File: tb/test_caravel_wrap.py
# Description: Caravel-shaped wrapper: 38-bit io_in stream + Wishbone reads.
# =============================================================================
import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

BEAT_BYTES = 4
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
        chunk = data[off:off + BEAT_BYTES]
        off += len(chunk)
        pad = chunk + b"\x00" * (BEAT_BYTES - len(chunk))
        keep = (1 << len(chunk)) - 1
        word = (int.from_bytes(pad, "little") & 0xFFFFFFFF) | (keep << 32)
        if off >= len(data):
            word |= 1 << 37
        # io_in[36] is tvalid; drive it with the data word.
        dut.io_in.value = word | (1 << 36)
        await RisingEdge(dut.wb_clk_i)
        guard = 0
        while (int(dut.io_out.value) & 1) == 0:
            await RisingEdge(dut.wb_clk_i)
            guard += 1
            if guard > 20000:
                raise TimeoutError("parser backpressure stuck")
    dut.io_in.value = 0
    await RisingEdge(dut.wb_clk_i)


async def wb_read(dut, word_addr):
    dut.wbs_cyc_i.value = 1
    dut.wbs_stb_i.value = 1
    dut.wbs_we_i.value = 0
    dut.wbs_adr_i.value = word_addr << 2
    await RisingEdge(dut.wb_clk_i)
    await Timer(1, unit="ns")
    assert int(dut.wbs_ack_o.value) == 1, f"no ack for word {word_addr}"
    data = int(dut.wbs_dat_o.value)
    dut.wbs_cyc_i.value = 0
    dut.wbs_stb_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    return data


@cocotb.test()
async def test_caravel_wrap(dut):
    cocotb.start_soon(Clock(dut.wb_clk_i, 3100, unit="ps").start())
    dut.wb_rst_i.value = 1
    dut.io_in.value = 0
    dut.wbs_cyc_i.value = 0
    dut.wbs_stb_i.value = 0
    dut.wbs_we_i.value = 0
    dut.wbs_sel_i.value = 0xF
    dut.wbs_dat_i.value = 0
    dut.wbs_adr_i.value = 0
    dut.la_data_in.value = 0
    dut.la_oenb.value = 0
    for _ in range(6):
        await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)

    assert (int(dut.io_oeb.value) & 1) == 0, "io_out[0] must be an output"
    assert int(dut.io_oeb.value) >> 1 == (1 << 37) - 1, "all other io are inputs"

    ref = 0x00C0FFEE12345678
    await send_bytes(dut, msg_add(4, ref, 300, 7777, 1))
    await send_bytes(dut, msg_cancel(4, ref, 30, 2))
    for _ in range(300):
        if (await wb_read(dut, 10)) >= 2:
            break

    assert await wb_read(dut, 0) == 2, "msg_count"
    word2 = await wb_read(dut, 2)
    assert (word2 >> 24) & 0xFF == ord("X"), f"type {word2:#x}"
    assert word2 & 0xFFFF == 4, f"locate {word2:#x}"
    assert await wb_read(dut, 4) == 30, "shares"
    assert await wb_read(dut, 6) == (ref & 0xFFFFFFFF), "ref low"
    assert await wb_read(dut, 7) == (ref >> 32), "ref high"

    dut._log.info("Caravel wrap: 2 messages over io_in, Wishbone reads OK PASS")
