# =============================================================================
# File: tb/run_multi_cocotb.py
# Description: Cocotb runner for the two-frame MoldUDP64 handoff test.
# =============================================================================
import os
import shutil
from cocotb_tools.runner import get_runner

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.abspath(os.path.join(HERE, "..", "rtl"))


def main():
    build_dir = "/tmp/cocotb_multi"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    runner = get_runner("icarus")
    runner.build(
        sources=[os.path.join(RTL, "moldudp64_pipeline.sv")],
        hdl_toplevel="moldudp64_pipeline",
        includes=[RTL],
        build_dir=build_dir,
        build_args=["-g2012"],
    )
    runner.test(hdl_toplevel="moldudp64_pipeline", test_module="test_mold_multi", test_dir=HERE, build_dir=build_dir)


if __name__ == "__main__":
    main()
