# ============================================================================
# File: tb/test_itch.py
# Description: Cocotb Testbench for ultra_low_latency_nasdaq_itch50_cutthrough.
# ============================================================================
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import os
import sys

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from golden_parser import GoldenITCHParser
from generate_pcaps import generate_stream

@cocotb.test()
async def test_itch_stream_regression(dut):
    """Verify ITCH 5.0 Core against Golden Parser under continuous burst streaming."""
    clock = Clock(dut.clk, 3100, unit="ps") # 3.10 ns = 322.26 MHz Target
    cocotb.start_soon(clock.start())

    # Initialize Inputs
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tlast.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    golden = GoldenITCHParser()
    raw_stream = generate_stream(count=1000, fuzz_ratio=0.01)
    golden.feed_bytes(raw_stream)

    expected_msgs = []
    while True:
        m = golden.parse_one()
        if m is None:
            break
        expected_msgs.append(m)

    dut._log.info(f"Generated {len(expected_msgs)} expected ITCH messages from stream of {len(raw_stream)} bytes.")

    # Driver Coroutine
    received_msgs = []
    
    async def driver():
        offset = 0
        while offset < len(raw_stream):
            await RisingEdge(dut.clk)
            if dut.s_axis_tready.value == 1:
                chunk = raw_stream[offset:offset+16]
                if len(chunk) < 16:
                    chunk = chunk + (b'\x00' * (16 - len(chunk)))
                word = int.from_bytes(chunk, 'little')
                dut.s_axis_tdata.value = word
                dut.s_axis_tvalid.value = 1
                offset += 16
            else:
                dut.s_axis_tvalid.value = 0

        await RisingEdge(dut.clk)
        dut.s_axis_tvalid.value = 0

    # Monitor Coroutine
    async def monitor():
        while len(received_msgs) < len(expected_msgs):
            await RisingEdge(dut.clk)
            if dut.m_axis_order_valid.value == 1:
                rec = {
                    'msg_type': int(dut.m_order_type.value),
                    'stock_locate': int(dut.m_stock_locate.value),
                    'tracking_number': int(dut.m_tracking_number.value),
                    'timestamp': int(dut.m_timestamp.value),
                    'order_ref_num': int(dut.m_order_ref_num.value),
                    'new_order_ref_num': int(dut.m_new_order_ref_num.value),
                    'side': int(dut.m_side.value),
                    'shares': int(dut.m_shares.value),
                    'stock': int(dut.m_stock.value),
                    'price': int(dut.m_price.value),
                    'match_number': int(dut.m_match_number.value),
                    'mpid': int(dut.m_mpid.value),
                    'printable': int(dut.m_printable.value),
                    'is_trade': int(dut.m_is_trade.value),
                    'is_drop': int(dut.m_is_drop.value),
                    'error_corrupt': int(dut.m_error_corrupt.value)
                }
                received_msgs.append(rec)

    cocotb.start_soon(driver())
    cocotb.start_soon(monitor())

    # Wait for monitor completion or timeout
    cycles = 0
    while len(received_msgs) < len(expected_msgs) and cycles < 10000:
        await RisingEdge(dut.clk)
        cycles += 1

    dut._log.info(f"Completed regression: Processed {len(received_msgs)}/{len(expected_msgs)} messages in {cycles} cycles.")
    assert len(received_msgs) == len(expected_msgs), f"Mismatch in count: {len(received_msgs)} vs {len(expected_msgs)}"

    for idx, (exp, got) in enumerate(zip(expected_msgs, received_msgs)):
        assert exp['msg_type'] == got['msg_type'], f"Msg {idx} Type mismatch: {exp['msg_type']} vs {got['msg_type']}"
        assert exp['is_trade'] == got['is_trade'], f"Msg {idx} is_trade mismatch"
        assert exp['is_drop'] == got['is_drop'], f"Msg {idx} is_drop mismatch"
        assert exp['error_corrupt'] == got['error_corrupt'], f"Msg {idx} error_corrupt mismatch"
        if not exp['error_corrupt']:
            assert exp['stock_locate'] == got['stock_locate'], f"Msg {idx} stock_locate mismatch"

    dut._log.info("ALL COCOTB REGRESSION TESTS PASSED (0 ERRORS).")