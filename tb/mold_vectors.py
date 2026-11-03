# =============================================================================
# File: tb/mold_vectors.py
# Description: Build Ethernet/IPv4/UDP/MoldUDP64 frames for RTL tests.
# =============================================================================
import struct


def mold_header(seq: int, count: int, session: bytes = b"SESSION001") -> bytes:
    assert len(session) == 10
    return session + seq.to_bytes(8, "big") + count.to_bytes(2, "big")


def mold_packet(seq: int, messages: list[bytes]) -> bytes:
    p = mold_header(seq, len(messages))
    for m in messages:
        p += len(m).to_bytes(2, "big") + m
    return p


def eth_ip_udp(payload: bytes, dst_ip: bytes = bytes([233, 54, 12, 111]),
               dst_port: int = 26400) -> bytes:
    eth = bytes([0x01, 0x00, 0x5E, 0x36, 0x0C, 0x6F]) + \
          bytes([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]) + b"\x08\x00"
    ip_len = 20 + 8 + len(payload)
    ip = (b"\x45\x00" + ip_len.to_bytes(2, "big") + b"\x00\x00\x40\x00\x40\x11\x00\x00"
          + bytes([10, 0, 0, 1]) + dst_ip)
    udp = (12345).to_bytes(2, "big") + dst_port.to_bytes(2, "big") + \
          (8 + len(payload)).to_bytes(2, "big") + b"\x00\x00"
    return eth + ip + udp + payload


def eth_mold_frame(seq: int, messages: list[bytes], dst_port: int = 26400) -> bytes:
    return eth_ip_udp(mold_packet(seq, messages), dst_port=dst_port)
