# =============================================================================
# File: tb/run_ab_system_cocotb.py
# Description: Cocotb runner for rtl/mold_ab_system.sv (two feeds + arbiter).
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_ab_sys"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[os.path.join(RTL, "mold_ab_system.sv")],
        hdl_toplevel="mold_ab_system",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="mold_ab_system", test_module="test_ab_system", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
