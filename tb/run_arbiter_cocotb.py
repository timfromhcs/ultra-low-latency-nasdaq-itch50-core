# =============================================================================
# File: tb/run_arbiter_cocotb.py
# Description: Cocotb runner for rtl/mold_feed_arbiter.sv.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_arb"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[os.path.join(RTL, "mold_feed_arbiter.sv")],
        hdl_toplevel="mold_feed_arbiter",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="mold_feed_arbiter", test_module="test_arbiter", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
