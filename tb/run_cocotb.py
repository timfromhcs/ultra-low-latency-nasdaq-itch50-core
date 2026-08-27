from cocotb_tools.runner import get_runner
import os
import shutil

def test_runner():
    build_dir = "/tmp/cocotb_build"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir, exist_ok=True)
    
    # Copy sources into clean workspace to avoid path space issues
    rtl_dir = "/tmp/cocotb_build/rtl"
    os.makedirs(rtl_dir, exist_ok=True)
    for f in ["itch_pkg.sv", "itch_drop_gate.sv", "itch_parser_core.sv", "itch_shifter.sv", "itch_top.sv"]:
        shutil.copy(os.path.join("rtl", f), os.path.join(rtl_dir, f))
    
    sources = [
        os.path.join(rtl_dir, "itch_pkg.sv"),
        os.path.join(rtl_dir, "itch_drop_gate.sv"),
        os.path.join(rtl_dir, "itch_parser_core.sv"),
        os.path.join(rtl_dir, "itch_shifter.sv"),
        os.path.join(rtl_dir, "itch_top.sv"),
    ]
    
    runner = get_runner("icarus")
    runner.build(
        sources=sources,
        hdl_toplevel="ultra_low_latency_nasdaq_itch50_cutthrough",
        includes=[rtl_dir],
        build_dir=build_dir,
        build_args=["-g2012"]
    )
    
    runner.test(
        hdl_toplevel="ultra_low_latency_nasdaq_itch50_cutthrough",
        test_module="test_itch",
        test_dir=os.path.abspath("tb"),
        build_dir=build_dir,
    )

if __name__ == "__main__":
    test_runner()