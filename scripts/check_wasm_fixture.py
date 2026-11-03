#!/usr/bin/env python3
"""Cross-check the Rust/WASM parser against the independent Python model."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tb"))
import itch_model as m

here = os.path.dirname(__file__)
stream = open(os.path.join(here, "..", "reports", "wasm_stream.bin"), "rb").read()
blob = open(os.path.join(here, "..", "reports", "wasm_records.bin"), "rb").read()

py = m.parse_stream(stream)
n = len(blob) // m.RECORD_SIZE
assert n == len(py), f"record count: wasm={n} python={len(py)}"
bad = 0
for i in range(n):
    w = blob[i * m.RECORD_SIZE:(i + 1) * m.RECORD_SIZE]
    p = py[i].pack()
    # Ignore the WASM-only latency field at offset 76.
    if w[:76] != p[:76]:
        bad += 1
        if bad < 5:
            print("mismatch at", i)
            for off in range(0, 76):
                if w[off] != p[off]:
                    print(f"  byte {off}: wasm={w[off]:02x} python={p[off]:02x}")
                    break
print(f"wasm_vs_python: {n} records, {bad} mismatches")
sys.exit(1 if bad else 0)
