#!/usr/bin/env python3
"""RTL mutation smoke test.

Injects a small set of semantic mutations into copies of the RTL and requires the
full-field Verilator regression to fail (kill) every mutant. A surviving mutant means
the test suite is too weak for that behaviour.

Run in WSL/Linux: python3 tools/mutate.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tb"))
import itch_model as m  # noqa: E402

MUTS = [
    ("drop_gate_A_len", "rtl/itch_drop_gate.sv", "`LEN_MSG_A", "8'd35"),
    ("parser_A_shares_offset", "rtl/itch_parser_core.sv",
     "parsed_shares        = {32'd0, bytes_20_23};", "parsed_shares        = {32'd0, bytes_21_24};"),
    ("parser_E_share_regression", "rtl/itch_parser_core.sv",
     "parsed_shares        = {32'd0, {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]}};",
     "parsed_shares        = {32'd0, bytes_20_23};"),
    ("shifter_no_append", "rtl/itch_shifter.sv",
     "assign next_count = post_consume_count + (accept ? word_bytes : 8'd0);",
     "assign next_count = post_consume_count;"),
    ("top_shares_zero", "rtl/itch_top.sv",
     "m_shares            <= core_shares;", "m_shares            <= 64'd0;"),
    ("locate_byte_swap", "rtl/itch_parser_core.sv",
     "wire [15:0] comm_locate = {window_data[15:8],  window_data[23:16]};",
     "wire [15:0] comm_locate = {window_data[23:16], window_data[15:8]};"),
    ("C_printable_invert", "rtl/itch_parser_core.sv",
     "parsed_printable     = (window_data[191:184] == 8'h59); // 'Y'",
     "parsed_printable     = (window_data[191:184] == 8'h4E); // 'N'"),
    ("Q_shares_truncate", "rtl/itch_parser_core.sv",
     "parsed_shares        = bytes_11_18; // full 64-bit cross quantity",
     "parsed_shares        = {32'd0, bytes_11_14};"),
    ("top_reference_zero", "rtl/itch_top.sv",
     "m_is_reference      <= core_is_reference;", "m_is_reference      <= 1'b0;"),
    ("shifter_consume_guard", "rtl/itch_shifter.sv",
     "(consume_bytes <= buf_count)", "(consume_bytes < buf_count)"),
]


def ensure_vectors():
    out = os.path.join(ROOT, "tb", "vectors_mut")
    if os.path.exists(os.path.join(out, "expected.bin")):
        return out
    m.generate_vectors(5000, 1337, out)
    return out


def run_mutant(name, path, old, new, vectors):
    work = tempfile.mkdtemp(prefix="chiplab_mut_")
    try:
        shutil.copytree(os.path.join(ROOT, "rtl"), os.path.join(work, "rtl"))
        shutil.copy(os.path.join(ROOT, "tb", "sim_main.cpp"), os.path.join(work, "sim_main.cpp"))
        shutil.copytree(vectors, os.path.join(work, "vectors"))
        target = os.path.join(work, path)
        src = open(target, encoding="utf-8").read()
        if old not in src:
            return "SKIP", "mutation anchor not found"
        open(target, "w", encoding="utf-8").write(src.replace(old, new, 1))
        build = subprocess.run(
            ["verilator", "-Wall", "-Wno-DECLFILENAME", "-Wno-fatal", "--coverage", "--cc", "-Irtl", "rtl/itch_top.sv",
             "--top-module", "ultra_low_latency_nasdaq_itch50_cutthrough", "--exe", "sim_main.cpp"],
            cwd=work, capture_output=True, text=True, timeout=180,
        )
        if build.returncode != 0:
            return "KILLED", "build failed: " + (build.stderr or build.stdout).strip()[-300:]
        mk = subprocess.run(
            ["make", "-j", "-C", "obj_dir", "-f",
             "Vultra_low_latency_nasdaq_itch50_cutthrough.mk",
             "Vultra_low_latency_nasdaq_itch50_cutthrough"],
            cwd=work, capture_output=True, text=True, timeout=180,
        )
        if mk.returncode != 0:
            return "KILLED", "compile failed: " + (mk.stderr or mk.stdout).strip()[-300:]
        r = subprocess.run(
            ["./obj_dir/Vultra_low_latency_nasdaq_itch50_cutthrough", "--vectors", "vectors", "--limit", "5000"],
            cwd=work, capture_output=True, text=True, timeout=120,
        )
        if r.returncode == 0:
            return "SURVIVED", (r.stdout or "").strip().splitlines()[-1] if r.stdout else ""
        return "KILLED", (r.stdout + r.stderr).strip().splitlines()[-1]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    vectors = ensure_vectors()
    rows = []
    for name, path, old, new in MUTS:
        status, detail = run_mutant(name, path, old, new, vectors)
        rows.append({"name": name, "status": status, "detail": detail})
        print(f"{status:9} {name}: {detail}")
    killed = sum(1 for r in rows if r["status"] == "KILLED")
    total = len(rows)
    report = {"total": total, "killed": killed, "score": round(100 * killed / total, 1), "rows": rows}
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    json.dump(report, open(os.path.join(ROOT, "reports", "mutation.json"), "w"), indent=2)
    print(f"mutation score: {report['score']}% ({killed}/{total})")
    return 0 if killed == total else 1


if __name__ == "__main__":
    sys.exit(main())
