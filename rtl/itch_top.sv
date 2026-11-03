// ============================================================================
// File: rtl/itch_top.sv
// Module: ultra_low_latency_nasdaq_itch50_cutthrough
// Description: NASDAQ ITCH 5.0 cut-through parser IP core (v2).
//
//   Interface additions vs. v1:
//     * s_axis_tkeep / s_axis_tlast are now functional (partial beats, framing)
//     * m_payload / m_msg_len preserve every message byte, including reference
//       data (Stock Directory etc.) that v1 discarded
//     * m_is_reference distinguishes reference data from actual drops
//     * m_shares is 64 bit (Cross Trade 'Q' carries a 64-bit quantity)
//     * message / byte / corrupt / frame counters for observability
//     * raw_pre_trigger_valid gates the L3 pre-trigger
//
//   Latency (honest reference points):
//     s_axis_tdata -> m_* registered output : 2 clocks (6.20 ns @ 322.26 MHz)
//     window_data  -> m_* registered output : 1 clock  (3.10 ns @ 322.26 MHz)
//     window_data  -> raw_* async bypass    : combinational mux delay
// ============================================================================
`ifndef ITCH_TOP_SV
`define ITCH_TOP_SV

`include "itch_pkg.sv"
`include "itch_drop_gate.sv"
`include "itch_parser_core.sv"
`include "itch_shifter.sv"

module ultra_low_latency_nasdaq_itch50_cutthrough #(
  parameter DATA_WIDTH   = 128,
  parameter BUFFER_BYTES = 128,
  parameter WINDOW_BYTES = 64
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // AXI4-Stream slave
  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [(DATA_WIDTH/8)-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  // Asynchronous combinatorial bypass (same cycle as window_data)
  output wire                        raw_order_valid,
  output wire [483:0]                raw_order_data,
  output wire [15:0]                 raw_stock_locate_pre_trigger,
  output wire                        raw_pre_trigger_valid,
  output wire [7:0]                  raw_msg_length,
  output wire                        raw_is_trade,
  output wire                        raw_is_reference,
  output wire                        raw_is_drop,
  output wire                        raw_is_corrupt,
  output wire [511:0]                raw_payload,
  output wire [7:0]                  status_buf_count,

  // Registered pipeline output (1 cycle from window, 2 cycles from tdata)
  output reg                         m_axis_order_valid,
  output reg  [7:0]                  m_order_type,
  output reg  [15:0]                 m_stock_locate,
  output reg  [15:0]                 m_tracking_number,
  output reg  [47:0]                 m_timestamp,
  output reg  [63:0]                 m_order_ref_num,
  output reg  [63:0]                 m_new_order_ref_num,
  output reg  [7:0]                  m_side,
  output reg  [63:0]                 m_shares,
  output reg  [63:0]                 m_stock,
  output reg  [31:0]                 m_price,
  output reg  [63:0]                 m_match_number,
  output reg  [31:0]                 m_mpid,
  output reg                         m_printable,
  output reg                         m_is_trade,
  output reg                         m_is_reference,
  output reg                         m_is_drop,
  output reg                         m_error_corrupt,
  output reg  [511:0]                m_payload,
  output reg  [7:0]                  m_msg_len,
  output reg  [7:0]                  m_event_code,
  output reg  [31:0]                 m_ref_value,

  // Observability
  output wire [31:0]                 status_msg_count,
  output wire [31:0]                 status_byte_count,
  output wire [31:0]                 status_corrupt_count,
  output wire [31:0]                 status_frame_count,
  output wire [31:0]                 status_beat_count,
  output wire                        status_last_pulse
);

  // --------------------------------------------------------------------------
  // Ingress de-framer / lookahead
  // --------------------------------------------------------------------------
  wire [511:0] window_data;
  wire [7:0]   window_valid_bytes;
  wire         window_has_msg;
  wire [7:0]   shifter_occupancy;

  wire         core_consume_valid;
  wire [7:0]   core_consume_bytes;

  itch_shifter #(
    .DATA_WIDTH    (DATA_WIDTH),
    .BYTES_PER_WORD(DATA_WIDTH/8),
    .WINDOW_BYTES  (WINDOW_BYTES),
    .BUFFER_BYTES  (BUFFER_BYTES)
  ) u_shifter (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tdata      (s_axis_tdata),
    .s_axis_tkeep      (s_axis_tkeep),
    .s_axis_tvalid     (s_axis_tvalid),
    .s_axis_tlast      (s_axis_tlast),
    .s_axis_tready     (s_axis_tready),
    .consume_valid     (core_consume_valid),
    .consume_bytes     (core_consume_bytes),
    .window_data       (window_data),
    .window_valid_bytes(window_valid_bytes),
    .window_has_msg    (window_has_msg),
    .buffer_occupancy  (shifter_occupancy),
    .last_pulse        (status_last_pulse),
    .beat_count        (status_beat_count),
    .frame_count       (status_frame_count)
  );

  assign status_buf_count = shifter_occupancy;

  // --------------------------------------------------------------------------
  // Decoder
  // --------------------------------------------------------------------------
  wire [7:0]  core_msg_type;
  wire [15:0] core_stock_locate;
  wire [15:0] core_tracking_number;
  wire [47:0] core_timestamp;
  wire [63:0] core_order_ref_num;
  wire [63:0] core_new_order_ref_num;
  wire [7:0]  core_side;
  wire [63:0] core_shares;
  wire [63:0] core_stock;
  wire [31:0] core_price;
  wire [63:0] core_match_number;
  wire [31:0] core_mpid;
  wire        core_printable;
  wire        core_is_trade;
  wire        core_is_reference;
  wire        core_is_drop;
  wire        core_error_corrupt;
  wire [511:0] core_payload;
  wire [7:0]  core_msg_len;
  wire [7:0]  core_event_code;
  wire [31:0] core_ref_value;

  wire [15:0] core_locate_pre_trigger;
  wire        core_pre_trigger_valid;
  wire [7:0]  core_gate_len;
  wire        core_msg_valid;
  wire        core_gate_trade;
  wire        core_gate_ref;
  wire        core_gate_drop;
  wire        core_gate_corrupt;

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
    .parsed_is_reference     (core_is_reference),
    .parsed_error_corrupt    (core_error_corrupt),
    .parsed_payload          (core_payload),
    .parsed_msg_length       (core_msg_len),
    .parsed_event_code       (core_event_code),
    .parsed_ref_value        (core_ref_value),
    .parsed_is_drop          (core_is_drop),
    .stock_locate_pre_trigger(core_locate_pre_trigger),
    .pre_trigger_valid       (core_pre_trigger_valid),
    .msg_length              (core_gate_len),
    .msg_valid               (core_msg_valid),
    .is_trade_msg            (core_gate_trade),
    .is_reference_msg        (core_gate_ref),
    .is_drop_msg             (core_gate_drop),
    .is_corrupt_msg          (core_gate_corrupt)
  );

  assign core_consume_valid = core_msg_valid;
  assign core_consume_bytes = core_error_corrupt ? 8'd1 : core_gate_len;

  // --------------------------------------------------------------------------
  // Async bypass
  // --------------------------------------------------------------------------
  assign raw_order_valid              = core_msg_valid;
  assign raw_order_data               = {core_msg_type, core_stock_locate, core_tracking_number, core_timestamp,
                                         core_order_ref_num, core_new_order_ref_num, core_side, core_shares,
                                         core_stock, core_price, core_match_number, core_mpid, core_printable,
                                         core_is_trade, core_is_reference, core_error_corrupt};
  assign raw_stock_locate_pre_trigger = core_locate_pre_trigger;
  assign raw_pre_trigger_valid        = core_pre_trigger_valid;
  assign raw_msg_length               = core_gate_len;
  assign raw_is_trade                 = core_gate_trade;
  assign raw_is_reference             = core_gate_ref;
  assign raw_is_drop                  = core_gate_drop;
  assign raw_is_corrupt               = core_gate_corrupt;
  assign raw_payload                  = core_payload;

  // --------------------------------------------------------------------------
  // Registered egress
  // --------------------------------------------------------------------------
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
      m_shares            <= 64'd0;
      m_stock             <= 64'd0;
      m_price             <= 32'd0;
      m_match_number      <= 64'd0;
      m_mpid              <= 32'd0;
      m_printable         <= 1'b0;
      m_is_trade          <= 1'b0;
      m_is_reference      <= 1'b0;
      m_is_drop           <= 1'b0;
      m_error_corrupt     <= 1'b0;
      m_payload           <= 512'd0;
      m_msg_len           <= 8'd0;
      m_event_code        <= 8'd0;
      m_ref_value         <= 32'd0;
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
      m_is_reference      <= core_is_reference;
      m_is_drop           <= core_is_drop;
      m_error_corrupt     <= core_error_corrupt;
      m_payload           <= core_payload;
      m_msg_len           <= core_msg_len;
      m_event_code        <= core_event_code;
      m_ref_value         <= core_ref_value;
    end
  end

  // --------------------------------------------------------------------------
  // Observability counters
  // --------------------------------------------------------------------------
  reg [31:0] msg_count_q;
  reg [31:0] byte_count_q;
  reg [31:0] corrupt_count_q;

  assign status_msg_count     = msg_count_q;
  assign status_byte_count    = byte_count_q;
  assign status_corrupt_count = corrupt_count_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      msg_count_q     <= 32'd0;
      byte_count_q    <= 32'd0;
      corrupt_count_q <= 32'd0;
    end else if (core_msg_valid) begin
      msg_count_q     <= msg_count_q + 32'd1;
      byte_count_q    <= byte_count_q + {24'd0, core_consume_bytes};
      if (core_error_corrupt)
        corrupt_count_q <= corrupt_count_q + 32'd1;
    end
  end

endmodule

`endif
