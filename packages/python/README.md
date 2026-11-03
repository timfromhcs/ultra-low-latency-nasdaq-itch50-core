# chiplab-itch

Independent NASDAQ ITCH 5.0 reference model from the ChipLab silicon lab.

It decodes **all 22 official opcodes**, preserves the full payload, and produces
the same 80-byte canonical record as the RTL, Wasm and browser implementations.

```bash
pip install chiplab-itch
chiplab-itch selfcheck --count 100000
chiplab-itch generate --count 100000 --out vectors
chiplab-itch parse --file vectors/stream.bin --limit 5
```

```python
from chiplab_itch import generate_stream, parse_stream

stream = generate_stream(100_000, seed=1337)
records = parse_stream(stream)
print(len(records), records[0].msg_type)
```

This package is a reference model, not a trading system and not a silicon
measurement. See the repository README for the verification evidence and the
honest limitations.
