#!/usr/bin/env python3
# =============================================================================
# File: tools/mutate_book.py
# Description: Mutation testing for the parser -> BBO path. Each mutant patches
#              a copy of rtl/ and runs tb/run_book_top_cocotb.py; a mutant is
#              KILLED when the test fails.
#
#   python3 tools/mutate_book.py
#   writes reports/mutation_book.json
# =============================================================================
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RUNNER = os.path.join(ROOT, "tb", "run_book_top_cocotb.py")

# (name, file, old, new)
MUTANTS = [
    ("replace_side_lost", "itch_top_of_book.sv",
     "wire add_bid = (s_msg_type == T_REPLACE && found) ? old_bid : ev_bid;",
     "wire add_bid = ev_bid;"),
    ("replace_old_slot", "itch_top_of_book.sv",
     "wire [7:0] new_base = {new_set, 2'b00};",
     "wire [7:0] new_base = ord_base;"),
    ("cancel_ignored", "itch_top_of_book.sv",
     "if (old_bid) lb_shares[loc_idx*LEVELS+rem_slot] <=\n                      lb_shares[loc_idx*LEVELS+rem_slot] - rm_amt;",
     "if (old_bid) lb_shares[loc_idx*LEVELS+rem_slot] <=\n                      lb_shares[loc_idx*LEVELS+rem_slot];"),
    ("ask_cancel_ignored", "itch_top_of_book.sv",
     "else         la_shares[loc_idx*LEVELS+rem_slot] <=\n                      la_shares[loc_idx*LEVELS+rem_slot] - rm_amt;",
     "else         la_shares[loc_idx*LEVELS+rem_slot] <=\n                      la_shares[loc_idx*LEVELS+rem_slot];"),
    ("bid_min_instead_of_max", "itch_top_of_book.sv",
     "if (lb_price[p_idx*LEVELS+j] > r_bid_p) begin",
     "if (lb_price[p_idx*LEVELS+j] < r_bid_p) begin"),
    ("ask_max_instead_of_min", "itch_top_of_book.sv",
     "if (la_price[p_idx*LEVELS+j] < r_ask_p) begin",
     "if (la_price[p_idx*LEVELS+j] > r_ask_p) begin"),
    ("trade_volume_ignored", "itch_top_of_book.sv",
     "vol[loc_idx]    <= vol[loc_idx] + s_shares;",
     "vol[loc_idx]    <= vol[loc_idx];"),
    ("last_price_zero", "itch_top_of_book.sv",
     "last_p[loc_idx] <= s_price;",
     "last_p[loc_idx] <= 32'd0;"),
    ("order_side_always_bid", "itch_top_of_book.sv",
     "ord_side[new_free_idx]   <= add_bid ? 8'h42 : 8'h53;",
     "ord_side[new_free_idx]   <= 8'h42;"),
]


def patch_tree(dst, rel, old, new):
    src_dir = os.path.join(ROOT, "rtl")
    dst_dir = os.path.join(dst, "rtl")
    shutil.copytree(src_dir, dst_dir)
    path = os.path.join(dst_dir, rel)
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    if text.count(old) != 1:
        raise RuntimeError(f"mutation pattern count {text.count(old)} in {rel}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(old, new))
    return dst_dir


def run_test(rtl_dir):
    env = dict(os.environ)
    env["CHIPLAB_RTL"] = rtl_dir
    proc = subprocess.run([sys.executable, RUNNER], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=600)
    out = proc.stdout + proc.stderr
    killed = "FAIL=0" not in out or proc.returncode != 0
    # cocotb prints "TESTS=n PASS=x FAIL=y"; treat any FAIL>0 as killed.
    for line in out.splitlines():
        if "TESTS=" in line and "FAIL=" in line:
            try:
                fail = int(line.split("FAIL=")[1].split()[0])
                killed = fail > 0
            except ValueError:
                pass
    return killed, out


def main():
    rows = []
    killed = 0
    for name, rel, old, new in MUTANTS:
        with tempfile.TemporaryDirectory(prefix="chiplab_mut_") as tmp:
            try:
                rtl_dir = patch_tree(tmp, rel, old, new)
                ok, out = run_test(rtl_dir)
            except Exception as exc:  # noqa: BLE001
                rows.append({"name": name, "status": "ERROR", "detail": str(exc)})
                continue
        status = "KILLED" if ok else "SURVIVED"
        if ok:
            killed += 1
        detail = ""
        for line in out.splitlines():
            if "AssertionError" in line or "MISMATCH" in line:
                detail = line.strip()[:160]
                break
        rows.append({"name": name, "status": status, "detail": detail})
        print(f"{status:8} {name} {detail}")

    report = {
        "total": len(MUTANTS),
        "killed": killed,
        "score": round(100.0 * killed / len(MUTANTS), 1),
        "rows": rows,
    }
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    with open(os.path.join(ROOT, "reports", "mutation_book.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    print(f"mutation_book: {killed}/{len(MUTANTS)} killed ({report['score']}%)")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
