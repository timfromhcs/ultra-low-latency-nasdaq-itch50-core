// ============================================================================
// File: rtl/itch_top.sv
// Module: ultra_low_latency_nasdaq_itch50_cutthrough
// Description: NASDAQ ITCH 5.0 Cut-Through Market Data Parser IP Core.
// ============================================================================
`ifndef ITCH_TOP_SV
`define ITCH_TOP_SV

`include "itch_pkg.sv"
`include "itch_drop_gate.sv"
`include "itch_parser_core.sv"
`include "itch_shifter.sv"

module ultra_low_latency_nasdaq_itch50_cutthrough #(
  parameter DATA_WIDTH = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // AXI4-Stream Slave Interface
  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  // Asynchronous Direct Combinatorial Bypass (<= 1.1ns Gate Delay)
  output wire                        raw_order_valid,
  output wire [451:0]                raw_order_data,
  output wire [15:0]                 raw_stock_locate_pre_trigger,
  output wire [7:0]                  raw_msg_length,
  output wire                        raw_is_trade,
  output wire                        raw_is_drop,
  output wire                        raw_is_corrupt,
  output wire [7:0]                  status_buf_count,

  // Registered Pipeline Output Interface (1-Cycle Latency)
  output reg                         m_axis_order_valid,
  output reg  [7:0]                  m_order_type,
  output reg  [15:0]                 m_stock_locate,
  output reg  [15:0]                 m_tracking_number,
  output reg  [47:0]                 m_timestamp,
  output reg  [63:0]                 m_order_ref_num,
  output reg  [63:0]                 m_new_order_ref_num,
  output reg  [7:0]                  m_side,
  output reg  [31:0]                 m_shares,
  output reg  [63:0]                 m_stock,
  output reg  [31:0]                 m_price,
  output reg  [63:0]                 m_match_number,
  output reg  [31:0]                 m_mpid,
  output reg                         m_printable,
  output reg                         m_is_trade,
  output reg                         m_is_drop,
  output reg                         m_error_corrupt
);

  wire [511:0] window_data;
  wire [7:0]   window_valid_bytes;
  wire         window_has_msg;
  wire [7:0]   shifter_occupancy;

  wire         core_consume_valid;
  wire [7:0]   core_consume_bytes;

  itch_shifter #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_shifter (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tdata      (s_axis_tdata),
    .s_axis_tvalid     (s_axis_tvalid),
    .s_axis_tlast      (s_axis_tlast),
    .s_axis_tready     (s_axis_tready),
    .consume_valid     (core_consume_valid),
    .consume_bytes     (core_consume_bytes),
    .window_data       (window_data),
    .window_valid_bytes(window_valid_bytes),
    .window_has_msg    (window_has_msg),
    .buffer_occupancy  (shifter_occupancy)
  );

  assign status_buf_count = shifter_occupancy;

  wire [7:0]  core_msg_type;
  wire [15:0] core_stock_locate;
  wire [15:0] core_tracking_number;
  wire [47:0] core_timestamp;
  wire [63:0] core_order_ref_num;
  wire [63:0] core_new_order_ref_num;
  wire [7:0]  core_side;
  wire [31:0] core_shares;
  wire [63:0] core_stock;
  wire [31:0] core_price;
  wire [63:0] core_match_number;
  wire [31:0] core_mpid;
  wire        core_printable;
  wire        core_is_trade;
  wire        core_is_drop;
  wire        core_error_corrupt;

  wire [15:0] core_locate_pre_trigger;
  wire [7:0]  core_msg_len;
  wire        core_msg_valid;
  /* verilator lint_off UNUSED */
  wire        core_gate_trade;
  wire        core_gate_drop;
  wire        core_gate_corrupt;
  /* verilator lint_on UNUSED */

  itch_parser_core u_parser_core (
    .window_data             (window_data),
    .window_valid_bytes      (window_valid_bytes),
    .enable_parser           (window_has_msg),
    .parsed_msg_type         (core_msg_type),
    .parsed_stock_locate     (core_stock_locate),
    .parsed_tracking_number  (core_tracking_number),
    .parsed_timestamp        (core_timestamp),
    .parsed_order_ref_num    (core_order_ref_num),
    .parsed_new_order_ref_num(core_new_order_ref_num),
    .parsed_side             (core_side),
    .parsed_shares           (core_shares),
    .parsed_stock            (core_stock),
    .parsed_price            (core_price),
    .parsed_match_number     (core_match_number),
    .parsed_mpid             (core_mpid),
    .parsed_printable        (core_printable),
    .parsed_is_trade         (core_is_trade),
    .parsed_is_drop          (core_is_drop),
    .parsed_error_corrupt    (core_error_corrupt),
    .stock_locate_pre_trigger(core_locate_pre_trigger),
    .msg_length              (core_msg_len),
    .msg_valid               (core_msg_valid),
    .is_trade_msg            (core_gate_trade),
    .is_drop_msg             (core_gate_drop),
    .is_corrupt_msg          (core_gate_corrupt)
  );

  assign core_consume_valid = core_msg_valid;
  assign core_consume_bytes = core_error_corrupt ? 8'd1 : core_msg_len;

  assign raw_order_valid              = core_msg_valid;
  assign raw_order_data               = {core_msg_type, core_stock_locate, core_tracking_number, core_timestamp,
                                         core_order_ref_num, core_new_order_ref_num, core_side, core_shares,
                                         core_stock, core_price, core_match_number, core_mpid, core_printable,
                                         core_is_trade, core_is_drop, core_error_corrupt};
  assign raw_stock_locate_pre_trigger = core_locate_pre_trigger;
  assign raw_msg_length               = core_msg_len;
  assign raw_is_trade                 = core_is_trade;
  assign raw_is_drop                  = core_is_drop;
  assign raw_is_corrupt               = core_error_corrupt;

  always @(posedge clk) begin
    if (!rst_n) begin
      m_axis_order_valid  <= 1'b0;
      m_order_type        <= 8'd0;
      m_stock_locate      <= 16'd0;
      m_tracking_number   <= 16'd0;
      m_timestamp         <= 48'd0;
      m_order_ref_num     <= 64'd0;
      m_new_order_ref_num <= 64'd0;
      m_side              <= 8'd0;
      m_shares            <= 32'd0;
      m_stock             <= 64'd0;
      m_price             <= 32'd0;
      m_match_number      <= 64'd0;
      m_mpid              <= 32'd0;
      m_printable         <= 1'b0;
      m_is_trade          <= 1'b0;
      m_is_drop           <= 1'b0;
      m_error_corrupt     <= 1'b0;
    end else begin
      m_axis_order_valid  <= core_msg_valid;
      m_order_type        <= core_msg_type;
      m_stock_locate      <= core_stock_locate;
      m_tracking_number   <= core_tracking_number;
      m_timestamp         <= core_timestamp;
      m_order_ref_num     <= core_order_ref_num;
      m_new_order_ref_num <= core_new_order_ref_num;
      m_side              <= core_side;
      m_shares            <= core_shares;
      m_stock             <= core_stock;
      m_price             <= core_price;
      m_match_number      <= core_match_number;
      m_mpid              <= core_mpid;
      m_printable         <= core_printable;
      m_is_trade          <= core_is_trade;
      m_is_drop           <= core_is_drop;
      m_error_corrupt     <= core_error_corrupt;
    end
  end

endmodule

`endif