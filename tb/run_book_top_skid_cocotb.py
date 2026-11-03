# =============================================================================
# File: tb/run_book_top_skid_cocotb.py
# Description: Cocotb runner for itch_top_book with INGRESS_SKID=1. Reuses the
#              parser->BBO test: the elastic stage must be functionally
#              transparent (same BBO events, same counters).
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.environ.get("CHIPLAB_RTL", os.path.abspath(os.path.join(HERE, "..", "rtl")))


def main():
    build_dir = "/tmp/cocotb_book_top_skid"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[
            os.path.join(RTL, "itch_top_book.sv"),
            os.path.join(RTL, "itch_metrics.sv"),
            os.path.join(RTL, "axis_skid_buffer.sv"),
        ],
        hdl_toplevel="itch_top_book",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012", "-Pitch_top_book.INGRESS_SKID=1"],
    )
    runner.test(hdl_toplevel="itch_top_book", test_module="test_book_top", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
