# ============================================================================
# File: tb/golden_parser.py
# Description: Independent Golden Reference Model for NASDAQ ITCH 5.0 Protocol.
# ============================================================================
import struct

# ITCH 5.0 Constants
MSG_SYSTEM_EVENT          = 0x53 # 'S' (12 bytes)
MSG_STOCK_DIRECTORY       = 0x52 # 'R' (39 bytes)
MSG_STOCK_TRADING_ACTION  = 0x48 # 'H' (25 bytes)
MSG_REG_SHO_RESTRICTION   = 0x59 # 'Y' (20 bytes)
MSG_MARKET_PARTICIPANT_POS= 0x4C # 'L' (26 bytes)
MSG_MWCB_DECLINE_LEVEL    = 0x56 # 'V' (35 bytes)
MSG_MWCB_STATUS           = 0x57 # 'W' (12 bytes)
MSG_QUOTING_PERIOD_UPDATE = 0x4B # 'K' (28 bytes)
MSG_LULD_AUCTION_COLLAR   = 0x4A # 'J' (35 bytes)
MSG_OPERATIONAL_HALT      = 0x68 # 'h' (21 bytes)

MSG_ADD_ORDER             = 0x41 # 'A' (36 bytes)
MSG_ADD_ORDER_MPID        = 0x46 # 'F' (40 bytes)
MSG_ORDER_EXECUTED        = 0x45 # 'E' (31 bytes)
MSG_ORDER_EXECUTED_PRICE  = 0x43 # 'C' (36 bytes)
MSG_ORDER_CANCEL          = 0x58 # 'X' (23 bytes)
MSG_ORDER_DELETE          = 0x44 # 'D' (19 bytes)
MSG_ORDER_REPLACE         = 0x55 # 'U' (35 bytes)

MSG_TRADE_NON_CROSS       = 0x50 # 'P' (44 bytes)
MSG_CROSS_TRADE           = 0x51 # 'Q' (40 bytes)
MSG_BROKEN_TRADE          = 0x42 # 'B' (19 bytes)
MSG_NOII                  = 0x49 # 'I' (50 bytes)
MSG_RPII                  = 0x4E # 'N' (20 bytes)

MSG_LENGTHS = {
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
    MSG_ADD_ORDER, MSG_ADD_ORDER_MPID, MSG_ORDER_EXECUTED, MSG_ORDER_EXECUTED_PRICE,
    MSG_ORDER_CANCEL, MSG_ORDER_DELETE, MSG_ORDER_REPLACE, MSG_TRADE_NON_CROSS, MSG_CROSS_TRADE
}

ADMIN_MSGS = {
    MSG_SYSTEM_EVENT, MSG_STOCK_DIRECTORY, MSG_STOCK_TRADING_ACTION, MSG_REG_SHO_RESTRICTION,
    MSG_MARKET_PARTICIPANT_POS, MSG_MWCB_DECLINE_LEVEL, MSG_MWCB_STATUS, MSG_QUOTING_PERIOD_UPDATE,
    MSG_LULD_AUCTION_COLLAR, MSG_OPERATIONAL_HALT, MSG_BROKEN_TRADE, MSG_NOII, MSG_RPII
}

class GoldenITCHParser:
    def __init__(self):
        self.buffer = bytearray()

    def feed_bytes(self, data: bytes):
        self.buffer.extend(data)

    def parse_one(self):
        if len(self.buffer) < 1:
            return None
        
        msg_type = self.buffer[0]
        if msg_type not in MSG_LENGTHS:
            # Corrupted / invalid opcode
            self.buffer.pop(0)
            return {
                'msg_type': msg_type,
                'stock_locate': 0,
                'tracking_number': 0,
                'timestamp': 0,
                'order_ref_num': 0,
                'new_order_ref_num': 0,
                'side': 0,
                'shares': 0,
                'stock': 0,
                'price': 0,
                'match_number': 0,
                'mpid': 0,
                'printable': 0,
                'is_trade': 0,
                'is_drop': 0,
                'error_corrupt': 1,
                'length': 1
            }

        expected_len = MSG_LENGTHS[msg_type]
        if len(self.buffer) < expected_len:
            return None # Wait for full packet

        raw = bytes(self.buffer[:expected_len])
        del self.buffer[:expected_len]

        res = {
            'msg_type': msg_type,
            'stock_locate': struct.unpack('>H', raw[1:3])[0],
            'tracking_number': struct.unpack('>H', raw[3:5])[0],
            'timestamp': int.from_bytes(raw[5:11], 'big'),
            'order_ref_num': 0,
            'new_order_ref_num': 0,
            'side': 0,
            'shares': 0,
            'stock': 0,
            'price': 0,
            'match_number': 0,
            'mpid': 0,
            'printable': 0,
            'is_trade': 1 if msg_type in TRADE_MSGS else 0,
            'is_drop': 1 if msg_type in ADMIN_MSGS else 0,
            'error_corrupt': 0,
            'length': expected_len
        }

        if msg_type == MSG_ADD_ORDER: # 'A' (36 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['side'] = raw[19]
            res['shares'] = struct.unpack('>I', raw[20:24])[0]
            res['stock'] = struct.unpack('>Q', raw[24:32])[0]
            res['price'] = struct.unpack('>I', raw[32:36])[0]

        elif msg_type == MSG_ADD_ORDER_MPID: # 'F' (40 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['side'] = raw[19]
            res['shares'] = struct.unpack('>I', raw[20:24])[0]
            res['stock'] = struct.unpack('>Q', raw[24:32])[0]
            res['price'] = struct.unpack('>I', raw[32:36])[0]
            res['mpid'] = struct.unpack('>I', raw[36:40])[0]

        elif msg_type == MSG_ORDER_EXECUTED: # 'E' (31 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['shares'] = struct.unpack('>I', raw[19:23])[0]
            res['match_number'] = struct.unpack('>Q', raw[23:31])[0]

        elif msg_type == MSG_ORDER_EXECUTED_PRICE: # 'C' (36 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['shares'] = struct.unpack('>I', raw[19:23])[0]
            res['printable'] = 1 if raw[23] == 0x59 else 0
            res['match_number'] = struct.unpack('>Q', raw[24:32])[0]
            res['price'] = struct.unpack('>I', raw[32:36])[0]

        elif msg_type == MSG_ORDER_CANCEL: # 'X' (23 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['shares'] = struct.unpack('>I', raw[19:23])[0]

        elif msg_type == MSG_ORDER_DELETE: # 'D' (19 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]

        elif msg_type == MSG_ORDER_REPLACE: # 'U' (35 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['new_order_ref_num'] = struct.unpack('>Q', raw[19:27])[0]
            res['shares'] = struct.unpack('>I', raw[27:31])[0]
            res['price'] = struct.unpack('>I', raw[31:35])[0]

        elif msg_type == MSG_TRADE_NON_CROSS: # 'P' (44 bytes)
            res['order_ref_num'] = struct.unpack('>Q', raw[11:19])[0]
            res['side'] = raw[19]
            res['shares'] = struct.unpack('>I', raw[20:24])[0]
            res['stock'] = struct.unpack('>Q', raw[24:32])[0]
            res['price'] = struct.unpack('>I', raw[32:36])[0]
            res['match_number'] = struct.unpack('>Q', raw[36:44])[0]

        elif msg_type == MSG_CROSS_TRADE: # 'Q' (40 bytes)
            res['shares'] = struct.unpack('>I', raw[15:19])[0] # lower 32b of cross shares
            res['stock'] = struct.unpack('>Q', raw[19:27])[0]
            res['price'] = struct.unpack('>I', raw[27:31])[0]
            res['match_number'] = struct.unpack('>Q', raw[31:39])[0]

        return res