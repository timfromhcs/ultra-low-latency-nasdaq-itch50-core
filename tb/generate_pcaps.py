# ============================================================================
# File: tb/generate_pcaps.py
# Description: PCAP and ITCH 5.0 Synthetic Stream Generator using Scapy.
# ============================================================================
import os
import struct
import random
from scapy.all import Ether, IP, UDP, wrpcap

def build_itch_msg(msg_type, locate=101, tracking=1, ts=123456789, **kwargs):
    header = struct.pack('>BHH', msg_type, locate, tracking) + ts.to_bytes(6, 'big')
    if msg_type == 0x41: # 'A'
        ref = kwargs.get('ref', 10001)
        side = ord(kwargs.get('side', 'B'))
        shares = kwargs.get('shares', 500)
        stock = kwargs.get('stock', b'AAPL    ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        price = kwargs.get('price', 1502500)
        return header + struct.pack('>QBI8sI', ref, side, shares, stock, price)

    elif msg_type == 0x46: # 'F'
        ref = kwargs.get('ref', 10002)
        side = ord(kwargs.get('side', 'S'))
        shares = kwargs.get('shares', 300)
        stock = kwargs.get('stock', b'MSFT    ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        price = kwargs.get('price', 3105000)
        mpid = kwargs.get('mpid', b'NSDQ')
        if isinstance(mpid, str): mpid = mpid.encode('ascii').ljust(4)
        return header + struct.pack('>QBI8sI4s', ref, side, shares, stock, price, mpid)

    elif msg_type == 0x45: # 'E'
        ref = kwargs.get('ref', 10001)
        shares = kwargs.get('shares', 200)
        match_num = kwargs.get('match_num', 987654321)
        return header + struct.pack('>QIQ', ref, shares, match_num)

    elif msg_type == 0x43: # 'C'
        ref = kwargs.get('ref', 10001)
        shares = kwargs.get('shares', 100)
        printable = ord('Y' if kwargs.get('printable', True) else 'N')
        match_num = kwargs.get('match_num', 987654322)
        price = kwargs.get('price', 1502600)
        return header + struct.pack('>QIBQI', ref, shares, printable, match_num, price)

    elif msg_type == 0x58: # 'X'
        ref = kwargs.get('ref', 10001)
        shares = kwargs.get('shares', 100)
        return header + struct.pack('>QI', ref, shares)

    elif msg_type == 0x44: # 'D'
        ref = kwargs.get('ref', 10001)
        return header + struct.pack('>Q', ref)

    elif msg_type == 0x55: # 'U'
        orig_ref = kwargs.get('orig_ref', 10001)
        new_ref = kwargs.get('new_ref', 10005)
        shares = kwargs.get('shares', 600)
        price = kwargs.get('price', 1510000)
        return header + struct.pack('>QQII', orig_ref, new_ref, shares, price)

    elif msg_type == 0x50: # 'P'
        ref = kwargs.get('ref', 10001)
        side = ord(kwargs.get('side', 'B'))
        shares = kwargs.get('shares', 1000)
        stock = kwargs.get('stock', b'NVDA    ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        price = kwargs.get('price', 4500000)
        match_num = kwargs.get('match_num', 88888888)
        return header + struct.pack('>QBI8sIQ', ref, side, shares, stock, price, match_num)

    elif msg_type == 0x51: # 'Q'
        shares = kwargs.get('shares', 50000)
        stock = kwargs.get('stock', b'GOOGL   ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        price = kwargs.get('price', 1350000)
        match_num = kwargs.get('match_num', 77777777)
        cross_type = ord(kwargs.get('cross_type', 'O'))
        return header + struct.pack('>Q8sIQc', shares, stock, price, match_num, bytes([cross_type]))

    elif msg_type == 0x53: # 'S' (System event, 12 bytes)
        return header + struct.pack('c', b'O')

    elif msg_type == 0x52: # 'R' (Stock directory, 39 bytes)
        stock = kwargs.get('stock', b'TSLA    ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        return header + struct.pack('8s20s', stock, b'\x00'*20)

    elif msg_type == 0x48: # 'H' (Trading action, 25 bytes)
        stock = kwargs.get('stock', b'AMZN    ')
        if isinstance(stock, str): stock = stock.encode('ascii').ljust(8)
        return header + struct.pack('8s6s', stock, b'\x00'*6)

    else:
        # Default padding
        return header + (b'\x00' * 8)

def generate_stream(count=100000, fuzz_ratio=0.01):
    stream = bytearray()
    types = [0x41, 0x46, 0x45, 0x43, 0x58, 0x44, 0x55, 0x50, 0x51, 0x53, 0x52, 0x48]
    stocks = [b'AAPL    ', b'MSFT    ', b'NVDA    ', b'GOOGL   ', b'AMZN    ', b'TSLA    ']

    for i in range(count):
        if random.random() < fuzz_ratio:
            # Corrupted opcode
            stream.append(random.choice([0x00, 0xFF, 0x7F, 0x11, 0xEE]))
        else:
            mtype = random.choice(types)
            locate = random.randint(1, 1000)
            tracking = i & 0xFFFF
            ts = 1000000000 + i
            stock = random.choice(stocks)
            shares = random.randint(10, 50000)
            price = random.randint(10000, 5000000)
            ref = 100000 + i
            msg = build_itch_msg(mtype, locate=locate, tracking=tracking, ts=ts,
                                 stock=stock, shares=shares, price=price, ref=ref)
            stream.extend(msg)
    return bytes(stream)

def generate_pcap(filename='tb/itch_sample.pcap', num_packets=100):
    packets = []
    stream = generate_stream(count=num_packets*10, fuzz_ratio=0.005)
    offset = 0
    seq = 1
    session = b'SESSION001'

    while offset < len(stream) and len(packets) < num_packets:
        chunk_len = min(random.randint(200, 1400), len(stream) - offset)
        payload = stream[offset:offset+chunk_len]
        offset += chunk_len

        # MoldUDP64 Header: Session(10), Sequence(8), MsgCount(2)
        mold_hdr = struct.pack('>10sQH', session, seq, 1)
        seq += 1
        udp_payload = mold_hdr + payload

        pkt = Ether(src="00:11:22:33:44:55", dst="66:77:88:99:AA:BB") / \
              IP(src="192.168.10.1", dst="233.54.12.111") / \
              UDP(sport=12345, dport=9876) / \
              udp_payload
        packets.append(pkt)

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    wrpcap(filename, packets)
    print(f"Wrote {len(packets)} MoldUDP64/ITCH packets to {filename}")

if __name__ == '__main__':
    generate_pcap()