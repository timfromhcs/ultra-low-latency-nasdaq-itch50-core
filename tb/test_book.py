# =============================================================================
# File: tb/test_book.py
# Description: Random ITCH event stream against itch_top_of_book, compared with
#              an independent Python order-book model.
# =============================================================================
import os
import sys
import random
from collections import defaultdict

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

EMPTY_ASK = 0xFFFFFFFF


class Book:
    def __init__(self):
        self.orders = {}                      # locate -> {ref: [side, price, shares]}
        self.last = {}                        # locate -> (price, shares)
        self.vol = {}                         # locate -> shares
        self.next_ref = 1

    def bbo(self, locate):
        book = self.orders.get(locate, {})
        bids = [(p, s) for (side, p, s) in book.values() if side == "B"]
        asks = [(p, s) for (side, p, s) in book.values() if side == "S"]
        if bids:
            bp = max(p for p, _ in bids)
            bs = sum(s for p, s in bids if p == bp)
        else:
            bp, bs = 0, 0
        if asks:
            ap = min(p for p, _ in asks)
            as_ = sum(s for p, s in asks if p == ap)
        else:
            ap, as_ = EMPTY_ASK, 0
        lo, ls = self.last.get(locate, (0, 0))
        # Aggregate per price and take the top four levels on each side.
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
        ad += [(EMPTY_ASK, 0)] * (4 - len(ad))
        return dict(bid_p=bp, bid_s=bs, ask_p=ap, ask_s=as_, last_p=lo, last_s=ls,
                    vol=self.vol.get(locate, 0), bid_levels=bd, ask_levels=ad)

    def add(self, locate, side, price, shares):
        ref = self.next_ref
        self.next_ref += 1
        self.orders.setdefault(locate, {})[ref] = [side, price, shares]
        return ref

    def remove(self, locate, ref):
        self.orders.get(locate, {}).pop(ref, None)

    def execute(self, locate, ref, shares):
        o = self.orders.get(locate, {}).get(ref)
        if not o:
            return
        if o[2] <= shares:
            self.remove(locate, ref)
        else:
            o[2] -= shares

    def replace(self, locate, ref, side, price, shares):
        o = self.orders.get(locate, {}).get(ref)
        if o is not None:
            # ITCH U has no side field: the replacement keeps the old side.
            o[1], o[2] = price, shares
            return ref
        self.orders.setdefault(locate, {})[ref] = [side, price, shares]
        return ref

    def trade(self, locate, price, shares):
        self.last[locate] = (price, shares)
        self.vol[locate] = self.vol.get(locate, 0) + shares


async def drive(dut, event):
    """Wait for ready, present one event, return the DUT BBO after it settles."""
    guard = 0
    while int(dut.s_ready.value) == 0:
        await RisingEdge(dut.clk)
        guard += 1
        if guard > 5000:
            raise TimeoutError("book did not become ready")

    dut.s_valid.value = 1
    dut.s_msg_type.value = event["type"]
    dut.s_locate.value = event["locate"]
    dut.s_side.value = event["side"]
    dut.s_order_ref.value = event["ref"]
    dut.s_new_ref.value = event.get("new_ref", 0)
    dut.s_price.value = event["price"]
    dut.s_shares.value = event["shares"]
    await RisingEdge(dut.clk)
    dut.s_valid.value = 0

    for _ in range(ORDERS_WAIT):
        await RisingEdge(dut.clk)
        if int(dut.m_valid.value):
            try:
                return dict(
                    locate=int(dut.m_locate.value),
                    bid_p=int(dut.m_bid_price.value),
                    bid_s=int(dut.m_bid_shares.value),
                    ask_p=int(dut.m_ask_price.value),
                    ask_s=int(dut.m_ask_shares.value),
                    last_p=int(dut.m_last_price.value),
                    last_s=int(dut.m_last_shares.value),
                    vol=int(dut.m_volume.value),
                    bid_levels=[(int(dut.m_bid_p0.value), int(dut.m_bid_s0.value)),
                                (int(dut.m_bid_p1.value), int(dut.m_bid_s1.value)),
                                (int(dut.m_bid_p2.value), int(dut.m_bid_s2.value)),
                                (int(dut.m_bid_p3.value), int(dut.m_bid_s3.value))],
                    ask_levels=[(int(dut.m_ask_p0.value), int(dut.m_ask_s0.value)),
                                (int(dut.m_ask_p1.value), int(dut.m_ask_s1.value)),
                                (int(dut.m_ask_p2.value), int(dut.m_ask_s2.value)),
                                (int(dut.m_ask_p3.value), int(dut.m_ask_s3.value))],
                )
            except ValueError:
                dut._log.info(
                    f"X value: loc={dut.m_locate.value} bid={dut.m_bid_price.value} "
                    f"ask={dut.m_ask_price.value} last={dut.m_last_price.value} "
                    f"vol={dut.m_volume.value} p_idx={dut.p_idx.value} "
                    f"init_done={dut.init_done.value}")
                raise
    raise TimeoutError("no m_valid after event")


ORDERS_WAIT = 600


@cocotb.test()
async def test_random_book(dut):
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_msg_type.value = 0
    dut.s_locate.value = 0
    dut.s_side.value = 0
    dut.s_order_ref.value = 0
    dut.s_new_ref.value = 0
    dut.s_price.value = 0
    dut.s_shares.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    rng = random.Random(99)
    book = Book()
    refs = {loc: [] for loc in range(1, 5)}
    checked = 0

    def price(side):
        # Four levels per side keeps the RTL level table (16 per side) honest.
        base = 9900 if side == "B" else 10100
        return base + 50 * rng.randrange(0, 4)

    for step in range(400):
        locate = rng.randrange(1, 5)
        live = [r for r in refs[locate] if r in book.orders.get(locate, {})]
        refs[locate] = live
        roll = rng.random()

        if roll < 0.45 or len(live) < 3:
            side = "B" if rng.random() < 0.5 else "S"
            px = price(side)
            sh = rng.randrange(1, 500)
            ref = book.add(locate, side, px, sh)
            refs[locate].append(ref)
            ev = dict(type=ord("A"), locate=locate, side=ord(side), ref=ref, price=px, shares=sh)
        elif roll < 0.55 and live:
            ref = rng.choice(live)
            sh = 1
            book.execute(locate, ref, sh)
            ev = dict(type=ord("E"), locate=locate, side=0, ref=ref, price=0, shares=sh)
        elif roll < 0.65 and live:
            ref = rng.choice(live)
            o = book.orders[locate][ref]
            sh = max(1, o[2] // 2) if o[2] > 1 else 1
            book.execute(locate, ref, sh)
            ev = dict(type=ord("X"), locate=locate, side=0, ref=ref, price=0, shares=sh)
        elif roll < 0.75 and live:
            ref = rng.choice(live)
            book.remove(locate, ref)
            ev = dict(type=ord("D"), locate=locate, side=0, ref=ref, price=0, shares=0)
        elif roll < 0.85 and live:
            ref = rng.choice(live)
            side = "B" if rng.random() < 0.5 else "S"
            px, sh = price(side), rng.randrange(1, 500)
            book.replace(locate, ref, side, px, sh)
            ev = dict(type=ord("U"), locate=locate, side=ord(side), ref=ref, new_ref=ref, price=px, shares=sh)
        else:
            side = "B" if rng.random() < 0.5 else "S"
            px, sh = price(side), rng.randrange(1, 500)
            book.trade(locate, px, sh)
            ev = dict(type=ord("P"), locate=locate, side=ord("B"), ref=0, price=px, shares=sh)

        got = await drive(dut, ev)
        exp = book.bbo(locate)
        exp["locate"] = locate
        if got != exp:
            dut._log.info(f"MISMATCH step {step} {ev}")
            dut._log.info(f"model locate {locate}: {book.orders.get(locate)}")
            for k in range(256):
                if int(dut.ord_valid[k].value):
                    dut._log.info(
                        f"rtl[{k}] ref={int(dut.ord_ref[k].value)} loc={int(dut.ord_locate[k].value)} "
                        f"side={int(dut.ord_side[k].value)} px={int(dut.ord_price[k].value)} "
                        f"sh={int(dut.ord_shares[k].value)}")
        assert got == exp, f"step {step} {ev}\n got {got}\n exp {exp}"
        checked += 1

    dut._log.info(f"Book: {checked} events, {int(dut.level_overflow.value)} level overflows, "
                  f"{int(dut.drops_overflow.value)} table overflows PASS")
    assert int(dut.level_overflow.value) == 0
    assert int(dut.drops_overflow.value) == 0


@cocotb.test()
async def test_no_stall_back_to_back(dut):
    """One event per cycle with s_ready high; the final BBO must match."""
    cocotb.start_soon(Clock(dut.clk, 3100, unit="ps").start())
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_msg_type.value = 0
    dut.s_locate.value = 0
    dut.s_side.value = 0
    dut.s_order_ref.value = 0
    dut.s_new_ref.value = 0
    dut.s_price.value = 0
    dut.s_shares.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    # Wait for the table init.
    guard = 0
    while int(dut.s_ready.value) == 0:
        await RisingEdge(dut.clk)
        guard += 1
        if guard > 5000:
            raise TimeoutError("init stuck")

    book = Book()
    events = []
    # 100 back-to-back adds across two locates and four levels per side.
    for n in range(100):
        locate = 1 + (n % 2)
        side = "B" if (n // 2) % 2 == 0 else "S"
        px = (9900 if side == "B" else 10100) + 50 * ((n // 4) % 4)
        sh = 10 + (n % 7)
        ref = book.add(locate, side, px, sh)
        events.append(dict(type=ord("A"), locate=locate, side=ord(side), ref=ref, price=px, shares=sh))

    last_expected = None
    for ev in events:
        assert int(dut.s_ready.value) == 1, "s_ready dropped: BBO stalled"
        dut.s_valid.value = 1
        dut.s_msg_type.value = ev["type"]
        dut.s_locate.value = ev["locate"]
        dut.s_side.value = ev["side"]
        dut.s_order_ref.value = ev["ref"]
        dut.s_price.value = ev["price"]
        dut.s_shares.value = ev["shares"]
        await RisingEdge(dut.clk)
        last_expected = book.bbo(ev["locate"])
        last_expected["locate"] = ev["locate"]

    dut.s_valid.value = 0
    got = None
    for _ in range(6):
        await RisingEdge(dut.clk)
        if int(dut.m_valid.value):
            got = dict(
                locate=int(dut.m_locate.value),
                bid_p=int(dut.m_bid_price.value),
                bid_s=int(dut.m_bid_shares.value),
                ask_p=int(dut.m_ask_price.value),
                ask_s=int(dut.m_ask_shares.value),
                last_p=int(dut.m_last_price.value),
                last_s=int(dut.m_last_shares.value),
                vol=int(dut.m_volume.value),
                bid_levels=[(int(dut.m_bid_p0.value), int(dut.m_bid_s0.value)),
                            (int(dut.m_bid_p1.value), int(dut.m_bid_s1.value)),
                            (int(dut.m_bid_p2.value), int(dut.m_bid_s2.value)),
                            (int(dut.m_bid_p3.value), int(dut.m_bid_s3.value))],
                ask_levels=[(int(dut.m_ask_p0.value), int(dut.m_ask_s0.value)),
                            (int(dut.m_ask_p1.value), int(dut.m_ask_s1.value)),
                            (int(dut.m_ask_p2.value), int(dut.m_ask_s2.value)),
                            (int(dut.m_ask_p3.value), int(dut.m_ask_s3.value))],
            )
    assert got == last_expected, f"back-to-back BBO\n got {got}\n exp {last_expected}"
    dut._log.info("No-stall: 100 events back-to-back, 1 event/cycle PASS")
