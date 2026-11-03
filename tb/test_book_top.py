# =============================================================================
# File: tb/test_book_top.py
# Description: End-to-end test: raw ITCH 5.0 bytes -> itch_top_book -> BBO.
#              The expected book is maintained independently in Python.
# =============================================================================
import os
import random
import sys
from collections import defaultdict

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

DATA_BYTES = 16
STOCK = b"AAPL    "


def hdr(t, locate, idx):
    return bytes([ord(t)]) + locate.to_bytes(2, "big") + (idx & 0xFFFF).to_bytes(2, "big") \
        + (34_200_000_000_000 + idx).to_bytes(6, "big")


def msg_add(locate, ref, side, shares, price, idx):
    return (hdr("A", locate, idx) + ref.to_bytes(8, "big") + side
            + shares.to_bytes(4, "big") + STOCK + price.to_bytes(4, "big"))


def msg_exec(locate, ref, shares, idx):
    return (hdr("E", locate, idx) + ref.to_bytes(8, "big") + shares.to_bytes(4, "big")
            + (0x12345678).to_bytes(8, "big"))


def msg_cancel(locate, ref, shares, idx):
    return hdr("X", locate, idx) + ref.to_bytes(8, "big") + shares.to_bytes(4, "big")


def msg_delete(locate, ref, idx):
    return hdr("D", locate, idx) + ref.to_bytes(8, "big")


def msg_replace(locate, old_ref, new_ref, shares, price, idx):
    return (hdr("U", locate, idx) + old_ref.to_bytes(8, "big") + new_ref.to_bytes(8, "big")
            + shares.to_bytes(4, "big") + price.to_bytes(4, "big"))


def msg_trade(locate, ref, side, shares, price, idx):
    return (hdr("P", locate, idx) + ref.to_bytes(8, "big") + side + shares.to_bytes(4, "big")
            + STOCK + price.to_bytes(4, "big") + (0xABCDEF).to_bytes(8, "big"))


class Book:
    def __init__(self):
        self.orders = {}
        self.last = {}
        self.vol = {}

    def apply(self, t, loc, ref, nref, side, price, shares):
        book = self.orders.setdefault(loc, {})
        if t in ("A", "F"):
            book[ref] = [side, price, shares]
        elif t in ("E", "C", "X", "D"):
            o = book.get(ref)
            if o:
                if t == "D" or o[2] <= shares:
                    book.pop(ref, None)
                else:
                    o[2] -= shares
        elif t == "U":
            o = book.get(ref)
            side2 = o[0] if o else side
            book.pop(ref, None)
            book[nref] = [side2, price, shares]
        elif t in ("P", "Q"):
            self.last[loc] = (price, shares)
            self.vol[loc] = self.vol.get(loc, 0) + shares

    def bbo(self, loc):
        book = self.orders.get(loc, {})
        bids = [(p, s) for side, p, s in book.values() if side == "B"]
        asks = [(p, s) for side, p, s in book.values() if side == "S"]
        bp = max((p for p, _ in bids), default=0)
        bs = sum(s for p, s in bids if p == bp) if bids else 0
        ap = min((p for p, _ in asks), default=0xFFFFFFFF)
        as_ = sum(s for p, s in asks if p == ap) if asks else 0
        lp, ls = self.last.get(loc, (0, 0))
        bagg = defaultdict(int)
        aagg = defaultdict(int)
        for side, p, s in book.values():
            if side == "B":
                bagg[p] += s
            else:
                aagg[p] += s
        bd = sorted(bagg.items(), reverse=True)[:4]
        ad = sorted(aagg.items())[:4]
        bd += [(0, 0)] * (4 - len(bd))
        ad += [(0xFFFFFFFF, 0)] * (4 - len(ad))
        return dict(locate=loc, bid_p=bp, bid_s=bs, ask_p=ap, ask_s=as_,
                    last_p=lp, last_s=ls, vol=self.vol.get(loc, 0),
                    bid_levels=bd, ask_levels=ad)


async def send_bytes(dut, data: bytes):
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


def build_stream():
    """Deterministic book-event stream with known refs and price levels."""
    rng = random.Random(7)
    msgs = []
    expected = []
    events = []
    snapshots = []
    book = Book()
    idx = 0
    next_ref = 1
    live = {1: [], 2: []}

    def emit(raw, t, loc, ref=0, nref=0, side="B", price=0, shares=0):
        nonlocal idx
        msgs.append(raw)
        book.apply(t, loc, ref, nref, side, price, shares)
        expected.append(book.bbo(loc))
        events.append((t, loc, ref, nref, side, price, shares))
        snapshots.append({l: dict(v) for l, v in book.orders.items()})
        idx += 1

    for loc in (1, 2):
        for level in range(4):
            for side in ("B", "S"):
                base = 9900 if side == "B" else 10100
                px = base + 50 * level
                for _ in range(2):
                    ref = next_ref
                    next_ref += 1
                    sh = rng.randrange(10, 500)
                    emit(msg_add(loc, ref, side.encode(), sh, px, idx), "A", loc, ref, side=side, price=px, shares=sh)
                    live[loc].append(ref)

    # Execute, cancel, delete, replace and trade.
    for step in range(120):
        loc = 1 + (step % 2)
        if not live[loc]:
            continue
        ref = rng.choice(live[loc])
        roll = step % 5
        if roll == 0:
            sh = 5
            emit(msg_exec(loc, ref, sh, idx), "E", loc, ref, shares=sh)
        elif roll == 1:
            sh = 7
            emit(msg_cancel(loc, ref, sh, idx), "X", loc, ref, shares=sh)
        elif roll == 2 and len(live[loc]) > 4:
            emit(msg_delete(loc, ref, idx), "D", loc, ref)
            live[loc].remove(ref)
        elif roll == 3:
            nref = next_ref
            next_ref += 1
            side = "B" if rng.random() < 0.5 else "S"
            base = 9900 if side == "B" else 10100
            px = base + 50 * rng.randrange(0, 4)
            sh = rng.randrange(10, 500)
            emit(msg_replace(loc, ref, nref, sh, px, idx), "U", loc, ref, nref, side=side, price=px, shares=sh)
            live[loc].remove(ref)
            live[loc].append(nref)
        else:
            side = "B" if rng.random() < 0.5 else "S"
            base = 9900 if side == "B" else 10100
            px = base + 50 * rng.randrange(0, 4)
            sh = rng.randrange(10, 500)
            emit(msg_trade(loc, ref, side.encode(), sh, px, idx), "P", loc, ref, side=side, price=px, shares=sh)

    return b"".join(msgs), expected, events, snapshots


@cocotb.test()
async def test_bytes_to_bbo(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    dut.s_axis_tdata.value = 0
    dut.cfg_max_shares.value = 0
    dut.cfg_collar.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    # Wait for the BBO table init (the parser is held in reset until then).
    guard = 0
    while int(dut.ready.value) == 0:
        await RisingEdge(dut.clk)
        guard += 1
        if guard > 5000:
            raise TimeoutError("book init stuck")

    data, expected, events, snapshots = build_stream()
    got = []

    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            if int(dut.bbo_valid.value):
                got.append(dict(
                    locate=int(dut.bbo_locate.value),
                    bid_p=int(dut.bbo_bid_price.value),
                    bid_s=int(dut.bbo_bid_shares.value),
                    ask_p=int(dut.bbo_ask_price.value),
                    ask_s=int(dut.bbo_ask_shares.value),
                    last_p=int(dut.bbo_last_price.value),
                    last_s=int(dut.bbo_last_shares.value),
                    vol=int(dut.bbo_volume.value),
                    bid_levels=[(int(dut.bbo_bid_p0.value), int(dut.bbo_bid_s0.value)),
                                (int(dut.bbo_bid_p1.value), int(dut.bbo_bid_s1.value)),
                                (int(dut.bbo_bid_p2.value), int(dut.bbo_bid_s2.value)),
                                (int(dut.bbo_bid_p3.value), int(dut.bbo_bid_s3.value))],
                    ask_levels=[(int(dut.bbo_ask_p0.value), int(dut.bbo_ask_s0.value)),
                                (int(dut.bbo_ask_p1.value), int(dut.bbo_ask_s1.value)),
                                (int(dut.bbo_ask_p2.value), int(dut.bbo_ask_s2.value)),
                                (int(dut.bbo_ask_p3.value), int(dut.bbo_ask_s3.value))],
                ))

    cocotb.start_soon(monitor())
    await send_bytes(dut, data)

    for _ in range(20000):
        if len(got) >= len(expected):
            break
        await RisingEdge(dut.clk)

    assert len(got) == len(expected), f"BBO events {len(got)} != messages {len(expected)}"
    for i, (a, b) in enumerate(zip(got, expected)):
        if a != b:
            dut._log.info(f"event {i}: {events[i]}")
            ref = events[i][2]
            base = (ref & 0x3F) * 4
            dut._log.info("rtl ways: " + ", ".join(
                f"{int(dut.u_book.ord_valid[base+w].value)}/{int(dut.u_book.ord_ref[base+w].value)}" for w in range(4)))
            dut._log.info(f"drops={int(dut.u_book.drops_overflow.value)} levels={int(dut.u_book.level_overflow.value)}")
            hist = [e for e in events[:i+1] if e[2] == ref or e[3] == ref]
            dut._log.info("history: " + " | ".join(str(h) for h in hist))
            found_rtl = [k for k in range(256) if int(dut.u_book.ord_valid[k].value) and int(dut.u_book.ord_ref[k].value) == ref]
            dut._log.info(f"rtl slots for ref: {found_rtl}")
            allv = [(k, int(dut.u_book.ord_ref[k].value), int(dut.u_book.ord_side[k].value), int(dut.u_book.ord_price[k].value), int(dut.u_book.ord_shares[k].value)) for k in range(256) if int(dut.u_book.ord_valid[k].value)]
            dut._log.info("rtl all: " + " | ".join(str(x) for x in allv[:20]))
            dut._log.info(f"model 1: {snapshots[i].get(1, {})}")
            dut._log.info(f"model 2: {snapshots[i].get(2, {})}")
        assert a == b, f"message {i} BBO\n got {a}\n exp {b}"
    dut._log.info(f"Top+book: {len(got)} messages, 0 mismatches PASS")

    # Performance counters observe the same parsed stream.
    for _ in range(8):
        await RisingEdge(dut.clk)
    mc = int(dut.metrics_msg_count.value)
    smc = int(dut.status_msg_count.value)
    hist = [int(getattr(dut, f"metrics_hist{i}").value) for i in range(8)]
    assert mc == smc == len(events), f"metrics {mc} status {smc} events {len(events)}"
    assert sum(hist) == mc, f"histogram sum {sum(hist)} != {mc}"
    assert int(dut.metrics_byte_count.value) > mc * 16, "byte counter too small"
    assert int(dut.metrics_cycle_count.value) > 0, "cycle counter"
    assert int(dut.metrics_occupancy_max.value) > 0, "occupancy_max not tracking"
    dut._log.info(
        f"Metrics: {mc} messages, {int(dut.metrics_byte_count.value)} bytes, "
        f"hist={hist}, occ_max={int(dut.metrics_occupancy_max.value)} PASS")
