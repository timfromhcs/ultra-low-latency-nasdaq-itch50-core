# =============================================================================
# File: tb/run_metrics_cocotb.py
# Description: Cocotb runner for rtl/itch_metrics.sv.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_metrics"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[os.path.join(RTL, "itch_metrics.sv")],
        hdl_toplevel="itch_metrics",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="itch_metrics", test_module="test_metrics", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
