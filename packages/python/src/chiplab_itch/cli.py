"""Command line interface for chiplab-itch."""
import argparse
import json
import sys
from .model import generate_stream, generate_vectors, parse_stream, LENGTHS


def cmd_generate(args):
    meta = generate_vectors(args.count, args.seed, args.out, args.corrupt_ratio)
    print(json.dumps(meta, indent=2))


def cmd_parse(args):
    data = open(args.file, "rb").read()
    records = parse_stream(data)
    for r in records[: args.limit]:
        print(json.dumps({k: (v if not isinstance(v, int) or abs(v) < 2**53 else str(v))
                          for k, v in r.as_dict().items()}, indent=None))
    print(f"# {len(records)} records, {len(data)} bytes", file=sys.stderr)


def cmd_selfcheck(args):
    stream = generate_stream(args.count, args.seed, 0.01)
    records = parse_stream(stream)
    assert len(records) == args.count, (len(records), args.count)
    types = {r.msg_type for r in records if not (r.flags & 4)}
    missing = set(LENGTHS) - types
    assert not missing, f"missing opcodes: {missing}"
    print(f"selfcheck OK: {len(records)} records, {len(types)} opcodes, {len(stream)} bytes")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="chiplab-itch")
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="generate stream.bin + expected.bin vectors")
    g.add_argument("--count", type=int, default=100_000)
    g.add_argument("--seed", type=int, default=1337)
    g.add_argument("--out", default="vectors")
    g.add_argument("--corrupt-ratio", type=float, default=0.01)
    g.set_defaults(func=cmd_generate)

    p = sub.add_parser("parse", help="parse a raw ITCH stream as JSONL")
    p.add_argument("--file", required=True)
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_parse)

    s = sub.add_parser("selfcheck", help="generate and validate all opcodes")
    s.add_argument("--count", type=int, default=10_000)
    s.add_argument("--seed", type=int, default=1337)
    s.set_defaults(func=cmd_selfcheck)

    args = ap.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
