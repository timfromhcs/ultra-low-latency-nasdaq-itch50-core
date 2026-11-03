# =============================================================================
# File: tb/run_skid_cocotb.py
# Description: Cocotb runner for rtl/axis_skid_buffer.sv.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_skid"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("verilator")
    runner.build(
        sources=[os.path.join(RTL, "axis_skid_buffer.sv")],
        hdl_toplevel="axis_skid_buffer",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-Wno-fatal", "--timing"],
    )
    runner.test(hdl_toplevel="axis_skid_buffer", test_module="test_skid", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
