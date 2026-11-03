// ============================================================================
// File: rtl/itch_top_book.sv
// Module: itch_top_book
// Description: End-to-end wrapper: ITCH parser -> locate-indexed top of book.
//              Feed raw ITCH 5.0 bytes on an AXI4-Stream slave and read the
//              per-message BBO on the `bbo_*` outputs.
//
//   The BBO consumes one decoded message per cycle (s_ready is always high), so
//   no FIFO is required between the parser and the book. Corrupt messages are
//   excluded from the book to avoid acting on a mis-decoded opcode.
// ============================================================================
`ifndef ITCH_TOP_BOOK_SV
`define ITCH_TOP_BOOK_SV

`include "itch_pkg.sv"
`include "itch_top.sv"
`include "itch_top_of_book.sv"

module itch_top_book #(
  parameter DATA_WIDTH = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [(DATA_WIDTH/8)-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  output wire                        bbo_valid,
  output wire [15:0]                 bbo_locate,
  output wire [31:0]                 bbo_bid_price,
  output wire [63:0]                 bbo_bid_shares,
  output wire [31:0]                 bbo_ask_price,
  output wire [63:0]                 bbo_ask_shares,
  output wire [31:0]                 bbo_last_price,
  output wire [63:0]                 bbo_last_shares,
  output wire [63:0]                 bbo_volume,

  output wire [31:0]                 bbo_bid_p0, bbo_bid_p1, bbo_bid_p2, bbo_bid_p3,
  output wire [63:0]                 bbo_bid_s0, bbo_bid_s1, bbo_bid_s2, bbo_bid_s3,
  output wire [31:0]                 bbo_ask_p0, bbo_ask_p1, bbo_ask_p2, bbo_ask_p3,
  output wire [63:0]                 bbo_ask_s0, bbo_ask_s1, bbo_ask_s2, bbo_ask_s3,

  output wire [31:0]                 status_msg_count,
  output wire [31:0]                 status_corrupt_count,
  output wire                        ready
);

  wire        m_axis_order_valid;
  wire [7:0]  m_order_type;
  wire [15:0] m_stock_locate;
  wire [63:0] m_order_ref_num;
  wire [63:0] m_new_order_ref_num;
  wire [7:0]  m_side;
  wire [63:0] m_shares;
  wire [31:0] m_price;
  wire        m_error_corrupt;
  wire        book_ready;

  // Hold the parser in reset until the book has cleared its tables, otherwise
  // messages parsed during the ~800-cycle init would be lost.
  assign ready = book_ready;

  /* verilator lint_off PINCONNECTEMPTY */
  ultra_low_latency_nasdaq_itch50_cutthrough #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_top (
    .clk(clk),
    .rst_n(rst_n && book_ready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .raw_order_valid(),
    .raw_order_data(),
    .raw_stock_locate_pre_trigger(),
    .raw_pre_trigger_valid(),
    .raw_msg_length(),
    .raw_is_trade(),
    .raw_is_reference(),
    .raw_is_drop(),
    .raw_is_corrupt(),
    .raw_payload(),
    .status_buf_count(),
    .m_axis_order_valid(m_axis_order_valid),
    .m_order_type(m_order_type),
    .m_stock_locate(m_stock_locate),
    .m_tracking_number(),
    .m_timestamp(),
    .m_order_ref_num(m_order_ref_num),
    .m_new_order_ref_num(m_new_order_ref_num),
    .m_side(m_side),
    .m_shares(m_shares),
    .m_stock(),
    .m_price(m_price),
    .m_match_number(),
    .m_mpid(),
    .m_printable(),
    .m_is_trade(),
    .m_is_reference(),
    .m_is_drop(),
    .m_error_corrupt(m_error_corrupt),
    .m_payload(),
    .m_msg_len(),
    .m_event_code(),
    .m_ref_value(),
    .status_msg_count(status_msg_count),
    .status_byte_count(),
    .status_corrupt_count(status_corrupt_count),
    .status_frame_count(),
    .status_beat_count(),
    .status_last_pulse()
  );

  itch_top_of_book u_book (
    .clk(clk),
    .rst_n(rst_n),
    .s_valid(m_axis_order_valid && !m_error_corrupt),
    .s_msg_type(m_order_type),
    .s_locate(m_stock_locate),
    .s_side(m_side),
    .s_order_ref(m_order_ref_num),
    .s_new_ref(m_new_order_ref_num),
    .s_price(m_price),
    .s_shares(m_shares),
    .s_ready(book_ready),
    .m_valid(bbo_valid),
    .m_locate(bbo_locate),
    .m_bid_price(bbo_bid_price),
    .m_bid_shares(bbo_bid_shares),
    .m_ask_price(bbo_ask_price),
    .m_ask_shares(bbo_ask_shares),
    .m_last_price(bbo_last_price),
    .m_last_shares(bbo_last_shares),
    .m_volume(bbo_volume),
    .m_bid_p0(bbo_bid_p0), .m_bid_p1(bbo_bid_p1), .m_bid_p2(bbo_bid_p2), .m_bid_p3(bbo_bid_p3),
    .m_bid_s0(bbo_bid_s0), .m_bid_s1(bbo_bid_s1), .m_bid_s2(bbo_bid_s2), .m_bid_s3(bbo_bid_s3),
    .m_ask_p0(bbo_ask_p0), .m_ask_p1(bbo_ask_p1), .m_ask_p2(bbo_ask_p2), .m_ask_p3(bbo_ask_p3),
    .m_ask_s0(bbo_ask_s0), .m_ask_s1(bbo_ask_s1), .m_ask_s2(bbo_ask_s2), .m_ask_s3(bbo_ask_s3),
    .drops_overflow(),
    .level_overflow(),
    .rescans(),
    .busy()
  );
  /* verilator lint_on PINCONNECTEMPTY */

endmodule

`endif
