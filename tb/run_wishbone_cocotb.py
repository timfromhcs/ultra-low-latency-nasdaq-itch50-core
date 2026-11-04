# =============================================================================
# File: tb/run_wishbone_cocotb.py
# Description: Cocotb runner for rtl/itch_wishbone_wrap.sv.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.environ.get("CHIPLAB_RTL", os.path.abspath(os.path.join(HERE, "..", "rtl")))


def main():
    build_dir = "/tmp/cocotb_wishbone"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[
            os.path.join(RTL, "itch_wishbone_wrap.sv"),
            os.path.join(RTL, "itch_host_wrap.sv"),
            os.path.join(RTL, "itch_top.sv"),
            os.path.join(RTL, "itch_drop_gate.sv"),
            os.path.join(RTL, "itch_parser_core.sv"),
            os.path.join(RTL, "itch_shifter.sv"),
            os.path.join(RTL, "itch_pkg.sv"),
        ],
        hdl_toplevel="itch_wishbone_wrap",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="itch_wishbone_wrap", test_module="test_wishbone", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
