# =============================================================================
# File: tb/run_mold_cocotb.py
# Description: Cocotb runner for rtl/moldudp64_frontend.sv using Verilator.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_mold"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    sources = [
        os.path.join(RTL, "itch_pkg.sv"),
        os.path.join(RTL, "moldudp64_frontend.sv"),
    ]
    runner = get_runner("verilator")
    runner.build(
        sources=sources,
        hdl_toplevel="moldudp64_frontend",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-Wno-fatal", "--timing"],
    )
    runner.test(
        hdl_toplevel="moldudp64_frontend",
        test_module="test_mold",
        test_dir=HERE,
        build_dir=build_dir,
    )


if __name__ == "__main__":
    main()
