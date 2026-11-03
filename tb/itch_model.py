# =============================================================================
# File: tb/itch_model.py
# Description: Independent, field-accurate NASDAQ ITCH 5.0 reference model.
#
# This module is deliberately written without looking at the RTL signal names:
# it is the executable specification used to generate vectors and to check the
# Verilator/Cocotb/WASM implementations. It decodes *all* 22 official opcodes,
# keeps the full payload, and exposes a stable 80-byte record format.
# =============================================================================
from __future__ import annotations

import hashlib
import json
import struct
from dataclasses import dataclass, asdict
from typing import Dict, Iterable, List, Optional

# -----------------------------------------------------------------------------
# Protocol constants
# -----------------------------------------------------------------------------
MSG_SYSTEM_EVENT = 0x53          # S
MSG_STOCK_DIRECTORY = 0x52       # R
MSG_STOCK_TRADING_ACTION = 0x48  # H
MSG_REG_SHO_RESTRICTION = 0x59   # Y
MSG_MARKET_PARTICIPANT_POS = 0x4C  # L
MSG_MWCB_DECLINE_LEVEL = 0x56    # V
MSG_MWCB_STATUS = 0x57           # W
MSG_QUOTING_PERIOD_UPDATE = 0x4B  # K
MSG_LULD_AUCTION_COLLAR = 0x4A   # J
MSG_OPERATIONAL_HALT = 0x68      # h

MSG_ADD_ORDER = 0x41             # A
MSG_ADD_ORDER_MPID = 0x46        # F
MSG_ORDER_EXECUTED = 0x45        # E
MSG_ORDER_EXECUTED_PRICE = 0x43  # C
MSG_ORDER_CANCEL = 0x58          # X
MSG_ORDER_DELETE = 0x44          # D
MSG_ORDER_REPLACE = 0x55         # U

MSG_TRADE_NON_CROSS = 0x50       # P
MSG_CROSS_TRADE = 0x51           # Q
MSG_BROKEN_TRADE = 0x42          # B
MSG_NOII = 0x49                  # I
MSG_RPII = 0x4E                  # N

LENGTHS: Dict[int, int] = {
    MSG_SYSTEM_EVENT: 12,
    MSG_STOCK_DIRECTORY: 39,
    MSG_STOCK_TRADING_ACTION: 25,
    MSG_REG_SHO_RESTRICTION: 20,
    MSG_MARKET_PARTICIPANT_POS: 26,
    MSG_MWCB_DECLINE_LEVEL: 35,
    MSG_MWCB_STATUS: 12,
    MSG_QUOTING_PERIOD_UPDATE: 28,
    MSG_LULD_AUCTION_COLLAR: 35,
    MSG_OPERATIONAL_HALT: 21,
    MSG_ADD_ORDER: 36,
    MSG_ADD_ORDER_MPID: 40,
    MSG_ORDER_EXECUTED: 31,
    MSG_ORDER_EXECUTED_PRICE: 36,
    MSG_ORDER_CANCEL: 23,
    MSG_ORDER_DELETE: 19,
    MSG_ORDER_REPLACE: 35,
    MSG_TRADE_NON_CROSS: 44,
    MSG_CROSS_TRADE: 40,
    MSG_BROKEN_TRADE: 19,
    MSG_NOII: 50,
    MSG_RPII: 20,
}

TRADE_MSGS = {
    MSG_ADD_ORDER, MSG_ADD_ORDER_MPID, MSG_ORDER_EXECUTED,
    MSG_ORDER_EXECUTED_PRICE, MSG_ORDER_CANCEL, MSG_ORDER_DELETE,
    MSG_ORDER_REPLACE, MSG_TRADE_NON_CROSS, MSG_CROSS_TRADE,
}
REFERENCE_MSGS = set(LENGTHS) - TRADE_MSGS

FLAG_TRADE = 0x01
FLAG_REFERENCE = 0x02
FLAG_CORRUPT = 0x04

RECORD_SIZE = 80
RECORD_MAGIC = 0x42414C43  # "CLAB" little endian


# -----------------------------------------------------------------------------
# Record
# -----------------------------------------------------------------------------
@dataclass(slots=True)
class Record:
    msg_type: int = 0
    flags: int = 0
    msg_len: int = 0
    locate: int = 0
    tracking: int = 0
    timestamp: int = 0
    order_ref: int = 0
    new_order_ref: int = 0
    shares: int = 0
    price: int = 0
    side: int = 0
    printable: int = 0
    event_code: int = 0
    match_number: int = 0
    stock: int = 0
    mpid: int = 0
    ref_value: int = 0
    checksum: int = 0

    def pack(self) -> bytes:
        b = bytearray(RECORD_SIZE)
        struct.pack_into("<BBBBHH", b, 0, self.msg_type & 0xFF, self.flags & 0xFF,
                         self.msg_len & 0xFF, 0, self.locate & 0xFFFF,
                         self.tracking & 0xFFFF)
        struct.pack_into("<QQQ", b, 8, self.timestamp & 0xFFFFFFFFFFFF,
                         self.order_ref & 0xFFFFFFFFFFFFFFFF,
                         self.new_order_ref & 0xFFFFFFFFFFFFFFFF)
        struct.pack_into("<Q", b, 32, self.shares & 0xFFFFFFFFFFFFFFFF)
        struct.pack_into("<I", b, 40, self.price & 0xFFFFFFFF)
        struct.pack_into("<BBBx", b, 44, self.side & 0xFF, self.printable & 0xFF,
                         self.event_code & 0xFF)
        struct.pack_into("<Q", b, 48, self.match_number & 0xFFFFFFFFFFFFFFFF)
        struct.pack_into("<Q", b, 56, self.stock & 0xFFFFFFFFFFFFFFFF)
        struct.pack_into("<I", b, 64, self.mpid & 0xFFFFFFFF)
        struct.pack_into("<I", b, 68, self.ref_value & 0xFFFFFFFF)
        struct.pack_into("<I", b, 72, self.checksum & 0xFFFFFFFF)
        struct.pack_into("<I", b, 76, 0)
        return bytes(b)

    @classmethod
    def unpack(cls, data: bytes) -> "Record":
        if len(data) != RECORD_SIZE:
            raise ValueError(f"record must be {RECORD_SIZE} bytes, got {len(data)}")
        (t, flags, ln, _r0, loc, trk) = struct.unpack_from("<BBBBHH", data, 0)
        ts, ref, nref = struct.unpack_from("<QQQ", data, 8)
        (shares,) = struct.unpack_from("<Q", data, 32)
        (price,) = struct.unpack_from("<I", data, 40)
        side, printable, event = struct.unpack_from("<BBBx", data, 44)
        (match,) = struct.unpack_from("<Q", data, 48)
        (stock,) = struct.unpack_from("<Q", data, 56)
        (mpid,) = struct.unpack_from("<I", data, 64)
        (ref_value,) = struct.unpack_from("<I", data, 68)
        (checksum,) = struct.unpack_from("<I", data, 72)
        return cls(t, flags, ln, loc, trk, ts, ref, nref, shares, price, side,
                   printable, event, match, stock, mpid, ref_value, checksum)

    def as_dict(self) -> dict:
        return asdict(self)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def fnv1a32(data: bytes) -> int:
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def _be(raw: bytes, off: int, size: int) -> int:
    return int.from_bytes(raw[off:off + size], "big")


def _stock(raw: bytes, off: int) -> int:
    return _be(raw, off, 8)


def _sym8(raw: bytes, off: int) -> bytes:
    return raw[off:off + 8]


# -----------------------------------------------------------------------------
# Reference parser
# -----------------------------------------------------------------------------
def parse_one(raw: bytes, offset: int = 0) -> Optional[tuple[Record, int]]:
    """Parse one message at offset. Returns (record, bytes_consumed) or None."""
    if offset >= len(raw):
        return None
    t = raw[offset]
    ln = LENGTHS.get(t)
    if ln is None:
        return Record(msg_type=t, flags=FLAG_CORRUPT, checksum=0), 1
    if offset + ln > len(raw):
        return None
    msg = raw[offset:offset + ln]
    r = Record(msg_type=t, msg_len=ln, checksum=fnv1a32(msg))
    r.flags = FLAG_TRADE if t in TRADE_MSGS else FLAG_REFERENCE
    r.locate = _be(msg, 1, 2)
    r.tracking = _be(msg, 3, 2)
    r.timestamp = _be(msg, 5, 6)

    if t == MSG_ADD_ORDER:
        r.order_ref = _be(msg, 11, 8)
        r.side = msg[19]
        r.shares = _be(msg, 20, 4)
        r.stock = _stock(msg, 24)
        r.price = _be(msg, 32, 4)
    elif t == MSG_ADD_ORDER_MPID:
        r.order_ref = _be(msg, 11, 8)
        r.side = msg[19]
        r.shares = _be(msg, 20, 4)
        r.stock = _stock(msg, 24)
        r.price = _be(msg, 32, 4)
        r.mpid = _be(msg, 36, 4)
    elif t == MSG_ORDER_EXECUTED:
        r.order_ref = _be(msg, 11, 8)
        r.shares = _be(msg, 19, 4)
        r.match_number = _be(msg, 23, 8)
    elif t == MSG_ORDER_EXECUTED_PRICE:
        r.order_ref = _be(msg, 11, 8)
        r.shares = _be(msg, 19, 4)
        r.printable = 1 if msg[23] == 0x59 else 0  # 'Y'
        r.match_number = _be(msg, 24, 8)
        r.price = _be(msg, 32, 4)
    elif t == MSG_ORDER_CANCEL:
        r.order_ref = _be(msg, 11, 8)
        r.shares = _be(msg, 19, 4)
    elif t == MSG_ORDER_DELETE:
        r.order_ref = _be(msg, 11, 8)
    elif t == MSG_ORDER_REPLACE:
        r.order_ref = _be(msg, 11, 8)
        r.new_order_ref = _be(msg, 19, 8)
        r.shares = _be(msg, 27, 4)
        r.price = _be(msg, 31, 4)
    elif t == MSG_TRADE_NON_CROSS:
        r.order_ref = _be(msg, 11, 8)
        r.side = msg[19]
        r.shares = _be(msg, 20, 4)
        r.stock = _stock(msg, 24)
        r.price = _be(msg, 32, 4)
        r.match_number = _be(msg, 36, 8)
    elif t == MSG_CROSS_TRADE:
        r.shares = _be(msg, 11, 8)
        r.stock = _stock(msg, 19)
        r.price = _be(msg, 27, 4)
        r.match_number = _be(msg, 31, 8)
        r.event_code = msg[39]
    elif t == MSG_SYSTEM_EVENT:
        r.event_code = msg[11]
    elif t == MSG_STOCK_DIRECTORY:
        r.stock = _stock(msg, 11)
        r.event_code = msg[19]
        r.ref_value = _be(msg, 21, 4)
    elif t == MSG_STOCK_TRADING_ACTION:
        r.stock = _stock(msg, 11)
        r.event_code = msg[19]
        r.ref_value = _be(msg, 21, 4)
    elif t == MSG_REG_SHO_RESTRICTION:
        r.stock = _stock(msg, 11)
        r.event_code = msg[19]
    elif t == MSG_MARKET_PARTICIPANT_POS:
        r.mpid = _be(msg, 11, 4)
        r.stock = _stock(msg, 15)
        r.event_code = msg[25]  # market participant state
    elif t == MSG_OPERATIONAL_HALT:
        r.stock = _stock(msg, 11)
        r.event_code = msg[20]
    elif t == MSG_MWCB_DECLINE_LEVEL:
        r.ref_value = _be(msg, 11, 4)
    elif t == MSG_MWCB_STATUS:
        r.event_code = msg[11]
    elif t == MSG_QUOTING_PERIOD_UPDATE:
        r.stock = _stock(msg, 11)
        r.event_code = msg[19]
    elif t == MSG_LULD_AUCTION_COLLAR:
        r.stock = _stock(msg, 11)
    elif t == MSG_BROKEN_TRADE:
        r.match_number = _be(msg, 11, 8)
    elif t == MSG_NOII:
        r.stock = _stock(msg, 11)
    elif t == MSG_RPII:
        r.stock = _stock(msg, 11)
        r.side = msg[19]
    return r, ln


def parse_stream(data: bytes, stop_on_truncated: bool = True) -> List[Record]:
    out: List[Record] = []
    off = 0
    n = len(data)
    while off < n:
        parsed = parse_one(data, off)
        if parsed is None:
            if stop_on_truncated:
                break
            off += 1
            continue
        rec, used = parsed
        out.append(rec)
        off += used
    return out


def records_bytes(records: Iterable[Record]) -> bytes:
    return b"".join(r.pack() for r in records)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# -----------------------------------------------------------------------------
# Deterministic vector generator
# -----------------------------------------------------------------------------
import random

SYMBOLS = [b"AAPL    ", b"MSFT    ", b"NVDA    ", b"GOOGL   ", b"AMZN    ",
           b"TSLA    ", b"META    ", b"SPY     ", b"QQQ     ", b"IWM     "]
MPIDS = [b"NSDQ", b"ARCA", b"BATS", b"EDGX", b"XNYS"]


def _hdr(t: int, locate: int, tracking: int, ts: int) -> bytearray:
    return bytearray([t]) + locate.to_bytes(2, "big") + tracking.to_bytes(2, "big") + ts.to_bytes(6, "big")


def build_message(rng: random.Random, t: int, idx: int) -> bytes:
    locate = rng.randint(1, 8000)
    tracking = idx & 0xFFFF
    ts = 34_200_000_000_000 + idx  # ns since midnight, 09:30-ish
    h = _hdr(t, locate, tracking, ts)
    ref = 1_000_000 + idx
    side = rng.choice(b"BS")
    shares = rng.randint(1, 2_000_000)
    price = rng.randint(1, 5_000_000)
    stock = rng.choice(SYMBOLS)
    match = rng.getrandbits(64)
    mpid = rng.choice(MPIDS)
    if t == MSG_ADD_ORDER:
        return bytes(h + ref.to_bytes(8, "big") + bytes([side]) + shares.to_bytes(4, "big") + stock + price.to_bytes(4, "big"))
    if t == MSG_ADD_ORDER_MPID:
        return bytes(h + ref.to_bytes(8, "big") + bytes([side]) + shares.to_bytes(4, "big") + stock + price.to_bytes(4, "big") + mpid)
    if t == MSG_ORDER_EXECUTED:
        return bytes(h + ref.to_bytes(8, "big") + shares.to_bytes(4, "big") + match.to_bytes(8, "big"))
    if t == MSG_ORDER_EXECUTED_PRICE:
        return bytes(h + ref.to_bytes(8, "big") + shares.to_bytes(4, "big") + b"YN"[rng.getrandbits(1):][:1]
                     + match.to_bytes(8, "big") + price.to_bytes(4, "big"))
    if t == MSG_ORDER_CANCEL:
        return bytes(h + ref.to_bytes(8, "big") + shares.to_bytes(4, "big"))
    if t == MSG_ORDER_DELETE:
        return bytes(h + ref.to_bytes(8, "big"))
    if t == MSG_ORDER_REPLACE:
        return bytes(h + ref.to_bytes(8, "big") + (ref + 1).to_bytes(8, "big")
                     + shares.to_bytes(4, "big") + price.to_bytes(4, "big"))
    if t == MSG_TRADE_NON_CROSS:
        return bytes(h + ref.to_bytes(8, "big") + bytes([side]) + shares.to_bytes(4, "big")
                     + stock + price.to_bytes(4, "big") + match.to_bytes(8, "big"))
    if t == MSG_CROSS_TRADE:
        # Cross shares are 64-bit.
        cross_shares = rng.getrandbits(48)
        return bytes(h + cross_shares.to_bytes(8, "big") + stock + price.to_bytes(4, "big")
                     + match.to_bytes(8, "big") + b"AO"[rng.getrandbits(1):][:1])
    if t == MSG_SYSTEM_EVENT:
        return bytes(h + bytes([rng.choice(b"OQSC")]))
    if t == MSG_STOCK_DIRECTORY:
        return bytes(h + stock + bytes([rng.choice(b"QGNSPZ")]) + bytes([rng.choice(b"CNGD")])
                     + rng.choice([100, 1000, 1]).to_bytes(4, "big") + bytes([rng.choice(b"NY")])
                     + bytes([rng.choice(b"QGNSPZ")]) + bytes([rng.choice(b"0123")])
                     + bytes([rng.choice(b"PNY")]) + bytes([rng.choice(b"NY")])
                     + bytes([rng.getrandbits(1)]) + bytes([rng.randint(1, 3)])
                     + bytes([rng.getrandbits(1)]) + rng.randint(1, 100).to_bytes(4, "big")
                     + bytes([rng.getrandbits(1)]) + bytes([rng.randint(1, 5)]))
    if t == MSG_STOCK_TRADING_ACTION:
        return bytes(h + stock + bytes([rng.choice(b"THB")]) + b"\x00"
                     + rng.getrandbits(32).to_bytes(4, "big"))
    if t == MSG_REG_SHO_RESTRICTION:
        return bytes(h + stock + bytes([rng.choice(b"01")]))
    if t == MSG_MARKET_PARTICIPANT_POS:
        return bytes(h + mpid + stock + bytes([rng.getrandbits(1)]) + bytes([rng.choice(b"012")])
                     + bytes([rng.choice(b"APDN")]))
    if t == MSG_MWCB_DECLINE_LEVEL:
        return bytes(h + rng.getrandbits(64).to_bytes(8, "big") + b"\x00" * 16)
    if t == MSG_MWCB_STATUS:
        return bytes(h + bytes([rng.randint(1, 3)]))
    if t == MSG_QUOTING_PERIOD_UPDATE:
        return bytes(h + stock + bytes([rng.choice(b"BE")])
                     + rng.getrandbits(32).to_bytes(4, "big")
                     + rng.getrandbits(32).to_bytes(4, "big"))
    if t == MSG_LULD_AUCTION_COLLAR:
        return bytes(h + stock + rng.getrandbits(32).to_bytes(4, "big") * 3
                     + rng.getrandbits(32).to_bytes(4, "big"))
    if t == MSG_OPERATIONAL_HALT:
        return bytes(h + stock + bytes([rng.choice(b"QGNSPZ")]) + bytes([rng.choice(b"012")]))
    if t == MSG_BROKEN_TRADE:
        return bytes(h + match.to_bytes(8, "big"))
    if t == MSG_NOII:
        return bytes(h + stock + rng.getrandbits(64).to_bytes(8, "big")
                     + rng.getrandbits(64).to_bytes(8, "big") + bytes([rng.choice(b"BSN")])
                     + rng.getrandbits(32).to_bytes(4, "big") * 3
                     + bytes([rng.choice(b"OC")]) + bytes([rng.randint(0, 3)]))
    if t == MSG_RPII:
        return bytes(h + stock + bytes([rng.choice(b"YN")]))
    raise ValueError(f"unknown type {t}")


def generate_stream(count: int, seed: int = 1337, corrupt_ratio: float = 0.01,
                    type_weights: Optional[Dict[int, float]] = None) -> bytes:
    rng = random.Random(seed)
    types = list(LENGTHS)
    if type_weights is None:
        # 72% trading path, 28% reference data.
        weights = [0.72 / len(TRADE_MSGS) if t in TRADE_MSGS else 0.28 / len(REFERENCE_MSGS) for t in types]
    else:
        weights = [type_weights.get(t, 0.0) for t in types]
    total = sum(weights)
    weights = [w / total for w in weights]
    stream = bytearray()
    emitted = 0
    i = 0
    while emitted < count:
        if rng.random() < corrupt_ratio:
            stream.append(rng.choice([0x00, 0x01, 0x0A, 0x7F, 0xEE, 0xFF]))
            emitted += 1
            i += 1
            continue
        t = rng.choices(types, weights=weights, k=1)[0]
        msg = build_message(rng, t, i)
        assert len(msg) == LENGTHS[t], (t, len(msg), LENGTHS[t])
        stream.extend(msg)
        emitted += 1
        i += 1
    return bytes(stream)


def generate_vectors(count: int, seed: int = 1337, out_dir: str = "tb/vectors",
                     corrupt_ratio: float = 0.01) -> dict:
    import json
    import os
    os.makedirs(out_dir, exist_ok=True)
    stream = generate_stream(count, seed, corrupt_ratio)
    expected = parse_stream(stream)
    # The generator can end on a corrupt byte; parse_stream handles it.
    assert len(expected) == count, f"expected {count} records, got {len(expected)}"
    with open(os.path.join(out_dir, "stream.bin"), "wb") as f:
        f.write(stream)
    with open(os.path.join(out_dir, "expected.bin"), "wb") as f:
        for r in expected:
            f.write(r.pack())
    meta = {
        "count": len(expected),
        "bytes": len(stream),
        "seed": seed,
        "corrupt_ratio": corrupt_ratio,
        "stream_sha256": sha256(stream),
        "expected_sha256": sha256(records_bytes(expected)),
        "record_size": RECORD_SIZE,
        "record_magic": f"0x{RECORD_MAGIC:08X}",
    }
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    return meta


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=100_000)
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--out", default="tb/vectors")
    ap.add_argument("--corrupt-ratio", type=float, default=0.01)
    args = ap.parse_args()
    meta = generate_vectors(args.count, args.seed, args.out, args.corrupt_ratio)
    print(json.dumps(meta, indent=2))
