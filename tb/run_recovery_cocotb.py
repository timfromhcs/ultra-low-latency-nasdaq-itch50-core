# =============================================================================
# File: tb/run_recovery_cocotb.py
# Description: Cocotb runner for rtl/mold_recovery.sv.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_recovery"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[os.path.join(RTL, "mold_recovery.sv")],
        hdl_toplevel="mold_recovery",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012", "-Pmold_recovery.TIMEOUT=16"],
    )
    runner.test(hdl_toplevel="mold_recovery", test_module="test_recovery", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
