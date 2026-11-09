# =============================================================================
# File: tb/run_caravel_upw_cocotb.py
# Description: Cocotb runner for the Caravel drop-in `user_project_wrapper`.
#   Reuses the Caravel wrapper test (same port names).
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
RTL = os.environ.get("CHIPLAB_RTL", os.path.join(ROOT, "rtl"))


def main():
    build_dir = "/tmp/cocotb_caravel_upw"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[
            os.path.join(ROOT, "caravel", "user_project_wrapper.v"),
            os.path.join(RTL, "itch_caravel_wrap.sv"),
            os.path.join(RTL, "itch_wishbone_wrap.sv"),
            os.path.join(RTL, "itch_host_wrap.sv"),
            os.path.join(RTL, "itch_top.sv"),
            os.path.join(RTL, "itch_drop_gate.sv"),
            os.path.join(RTL, "itch_parser_core.sv"),
            os.path.join(RTL, "itch_shifter.sv"),
            os.path.join(RTL, "itch_pkg.sv"),
        ],
        hdl_toplevel="user_project_wrapper",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="user_project_wrapper", test_module="test_caravel_wrap", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
