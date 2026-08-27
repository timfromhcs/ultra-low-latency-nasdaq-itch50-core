import json
import wavedrom
import os

wave_data = {
    "signal": [
        {"name": "clk", "wave": "p...........", "period": 1},
        {"name": "rst_n", "wave": "01.........."},
        {"name": "s_axis_tvalid", "wave": "0.1.1.1.1.0."},
        {"name": "s_axis_tready", "wave": "1..........."},
        {"name": "s_axis_tdata", "wave": "x.3.4.5.6.x.", "data": ["Word 0", "Word 1", "Word 2", "Word 3"]},
        {},
        {"name": "raw_order_valid (Async Bypass)", "wave": "0.1.1.1.1.0.", "node": "..a.b.c.d..."},
        {"name": "raw_locate_pre_trigger", "wave": "x.3.4.5.6.x.", "data": ["0x0042", "0x0088", "0x0104", "0x0200"]},
        {},
        {"name": "m_axis_order_valid (Registered)", "wave": "0..1.1.1.1.0", "node": "...A.B.C.D.."},
        {"name": "m_order_type", "wave": "x..3.4.5.6.x", "data": ["'A'", "'E'", "'C'", "'U'"]},
        {"name": "m_stock_locate", "wave": "x..3.4.5.6.x", "data": ["0x0042", "0x0088", "0x0104", "0x0200"]},
        {"name": "m_shares", "wave": "x..3.4.5.6.x", "data": ["500", "200", "100", "600"]},
        {"name": "m_price", "wave": "x..3.4.5.6.x", "data": ["$150.25", "-", "$150.26", "$151.00"]}
    ],
    "edge": [
        "a~>A 1 cycle (3.10ns)",
        "b~>B 1 cycle (3.10ns)",
        "c~>C 1 cycle (3.10ns)"
    ],
    "head": {
        "text": "NASDAQ ITCH 5.0 Cut-Through Latency & Speculative Pipeline Timing",
        "tick": 0
    }
}

os.makedirs("docs", exist_ok=True)
json_str = json.dumps(wave_data, indent=2)
with open("docs/timing_cutthrough.json", "w") as f:
    f.write(json_str)

svg = wavedrom.render(json_str)
svg.saveas("docs/timing_cutthrough.svg")
print("Saved docs/timing_cutthrough.json and docs/timing_cutthrough.svg successfully.")