# =============================================================================
# File: tb/test_model.py
# Description: Unit tests for the independent ITCH 5.0 reference model.
# Run: python -m pytest -q tb/test_model.py
# =============================================================================
import os
import sys
import struct

sys.path.insert(0, os.path.dirname(__file__))
import itch_model as m


def hdr(t, locate=42, tracking=7, ts=0x010203040506):
    return bytes([t]) + locate.to_bytes(2, "big") + tracking.to_bytes(2, "big") + ts.to_bytes(6, "big")


def test_add_order_all_fields():
    msg = (hdr(0x41) + (0x1122334455667788).to_bytes(8, "big") + b"S"
           + (123456).to_bytes(4, "big") + b"AAPL    " + (1502500).to_bytes(4, "big"))
    assert len(msg) == 36
    r, used = m.parse_one(msg)
    assert used == 36
    assert r.msg_type == 0x41 and r.flags == m.FLAG_TRADE
    assert r.locate == 42 and r.tracking == 7 and r.timestamp == 0x010203040506
    assert r.order_ref == 0x1122334455667788
    assert r.side == ord("S")
    assert r.shares == 123456
    assert r.stock == int.from_bytes(b"AAPL    ", "big")
    assert r.price == 1502500
    assert r.checksum == m.fnv1a32(msg)


def test_executed_shares_offset_regression():
    # E has no side byte: shares start at byte 19, not 20.
    msg = (hdr(0x45) + (9).to_bytes(8, "big") + (777).to_bytes(4, "big")
           + (0xDEADBEEF).to_bytes(8, "big"))
    assert len(msg) == 31
    r, _ = m.parse_one(msg)
    assert r.shares == 777
    assert r.match_number == 0xDEADBEEF

    # C has a printable byte at 23, match at 24, price at 32.
    msg = (hdr(0x43) + (9).to_bytes(8, "big") + (888).to_bytes(4, "big") + b"Y"
           + (0xCAFEBABE).to_bytes(8, "big") + (999).to_bytes(4, "big"))
    assert len(msg) == 36
    r, _ = m.parse_one(msg)
    assert r.shares == 888 and r.printable == 1
    assert r.match_number == 0xCAFEBABE and r.price == 999


def test_cross_trade_64bit_shares():
    msg = (hdr(0x51) + (0x0000000123456789).to_bytes(8, "big") + b"GOOGL   "
           + (1350000).to_bytes(4, "big") + (0x1234).to_bytes(8, "big") + b"O")
    assert len(msg) == 40
    r, _ = m.parse_one(msg)
    assert r.shares == 0x123456789
    assert r.stock == int.from_bytes(b"GOOGL   ", "big")
    assert r.price == 1350000
    assert r.match_number == 0x1234
    assert r.event_code == ord("O")


def test_stock_directory_reference_data():
    payload = (b"TSLA    " + b"Q" + b"N" + (100).to_bytes(4, "big") + b"Y"
               + b"Q" + b"1" + b"P" + b"N" + b"\x01" + b"\x02" + b"\x00"
               + (10).to_bytes(4, "big") + b"\x00" + b"\x03")
    msg = hdr(0x52) + payload
    assert len(msg) == 39
    r, _ = m.parse_one(msg)
    assert r.flags == m.FLAG_REFERENCE
    assert r.stock == int.from_bytes(b"TSLA    ", "big")
    assert r.event_code == ord("Q")
    assert r.ref_value == 100


def test_mpid_position_and_halt():
    msg = hdr(0x4C) + b"NSDQ" + b"AAPL    " + b"Y" + b"1" + b"A"
    assert len(msg) == 26
    r, _ = m.parse_one(msg)
    assert r.mpid == int.from_bytes(b"NSDQ", "big")
    assert r.stock == int.from_bytes(b"AAPL    ", "big")
    assert r.event_code == ord("A")

    msg = hdr(0x68) + b"MSFT    " + b"Q" + b"1"
    assert len(msg) == 21
    r, _ = m.parse_one(msg)
    assert r.stock == int.from_bytes(b"MSFT    ", "big")
    assert r.event_code == ord("1")


def test_corrupt_resync_and_truncated_tail():
    good = hdr(0x44) + (5).to_bytes(8, "big")
    data = b"\x00" + good + b"\x41\x42\x43"  # corrupt, D, 3-byte truncated A
    recs = m.parse_stream(data)
    assert len(recs) == 2
    assert recs[0].flags == m.FLAG_CORRUPT and recs[0].msg_len == 0
    assert recs[1].msg_type == 0x44 and recs[1].order_ref == 5


def test_record_pack_roundtrip():
    r = m.Record(msg_type=0x41, flags=1, msg_len=36, locate=7, tracking=9,
                 timestamp=123, order_ref=456, shares=789, price=1000,
                 stock=int.from_bytes(b"AAPL    ", "big"), checksum=0xDEADBEEF)
    blob = r.pack()
    assert len(blob) == m.RECORD_SIZE
    r2 = m.Record.unpack(blob)
    assert r2 == r


def test_generator_is_deterministic_and_complete():
    a = m.generate_stream(2000, seed=42, corrupt_ratio=0.02)
    b = m.generate_stream(2000, seed=42, corrupt_ratio=0.02)
    assert a == b
    recs = m.parse_stream(a)
    assert len(recs) == 2000
    types = {r.msg_type for r in recs if not (r.flags & m.FLAG_CORRUPT)}
    assert types == set(m.LENGTHS), f"missing opcodes: {set(m.LENGTHS) - types}"
