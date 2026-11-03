// ============================================================================
// File: formal/itch_formal.sv
// Module: itch_formal (SymbiYosys / yosys-smtbmc harness, v2)
// Description: Formal invariants for the v2 ITCH core.
//
//   The original harness mostly proved "the registered output is the delayed
//   combinational output", which is a tautology. This version adds:
//     * pre-trigger <-> decoded locate equivalence
//     * trade / reference / corrupt class exclusivity
//     * legal message length per opcode
//     * 1-cycle register equivalence for every canonical field
//     * deadlock / flow-control invariant
// ============================================================================
`include "itch_pkg.sv"
`include "itch_drop_gate.sv"
`include "itch_parser_core.sv"
`include "itch_shifter.sv"
`include "itch_top.sv"

module itch_formal (
  input  wire         clk,
  input  wire         formal_rst_n,
  input  wire [127:0] s_axis_tdata,
  input  wire         s_axis_tvalid,
  input  wire         s_axis_tlast
);

  // --------------------------------------------------------------------------
  // Reset sequencing
  // --------------------------------------------------------------------------
  reg [3:0] reset_cnt = 4'd0;
  always @(posedge clk) begin
    if (reset_cnt < 4'd5)
      reset_cnt <= reset_cnt + 4'd1;
  end
  wire rst_n = (reset_cnt >= 4'd4) && formal_rst_n;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  wire                        s_axis_tready;
  wire                        raw_order_valid;
  wire [483:0]                raw_order_data;
  wire [15:0]                 raw_locate_pre;
  wire                        raw_pre_valid;
  wire [7:0]                  raw_msg_length;
  wire                        raw_is_trade;
  wire                        raw_is_reference;
  wire                        raw_is_drop;
  wire                        raw_is_corrupt;
  wire [511:0]                raw_payload;
  wire [7:0]                  status_buf_count;

  wire                        m_axis_order_valid;
  wire [7:0]                  m_order_type;
  wire [15:0]                 m_stock_locate;
  wire [15:0]                 m_tracking_number;
  wire [47:0]                 m_timestamp;
  wire [63:0]                 m_order_ref_num;
  wire [63:0]                 m_new_order_ref_num;
  wire [7:0]                  m_side;
  wire [63:0]                 m_shares;
  wire [63:0]                 m_stock;
  wire [31:0]                 m_price;
  wire [63:0]                 m_match_number;
  wire [31:0]                 m_mpid;
  wire                        m_printable;
  wire                        m_is_trade;
  wire                        m_is_reference;
  wire                        m_is_drop;
  wire                        m_error_corrupt;
  wire [511:0]                m_payload;
  wire [7:0]                  m_msg_len;
  wire [7:0]                  m_event_code;
  wire [31:0]                 m_ref_value;
  wire [31:0]                 status_msg_count;
  wire [31:0]                 status_byte_count;
  wire [31:0]                 status_corrupt_count;
  wire [31:0]                 status_frame_count;
  wire [31:0]                 status_beat_count;
  wire                        status_last_pulse;

  ultra_low_latency_nasdaq_itch50_cutthrough #(
    .DATA_WIDTH(128)
  ) u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(4'hF),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .raw_order_valid(raw_order_valid),
    .raw_order_data(raw_order_data),
    .raw_stock_locate_pre_trigger(raw_locate_pre),
    .raw_pre_trigger_valid(raw_pre_valid),
    .raw_msg_length(raw_msg_length),
    .raw_is_trade(raw_is_trade),
    .raw_is_reference(raw_is_reference),
    .raw_is_drop(raw_is_drop),
    .raw_is_corrupt(raw_is_corrupt),
    .raw_payload(raw_payload),
    .status_buf_count(status_buf_count),
    .m_axis_order_valid(m_axis_order_valid),
    .m_order_type(m_order_type),
    .m_stock_locate(m_stock_locate),
    .m_tracking_number(m_tracking_number),
    .m_timestamp(m_timestamp),
    .m_order_ref_num(m_order_ref_num),
    .m_new_order_ref_num(m_new_order_ref_num),
    .m_side(m_side),
    .m_shares(m_shares),
    .m_stock(m_stock),
    .m_price(m_price),
    .m_match_number(m_match_number),
    .m_mpid(m_mpid),
    .m_printable(m_printable),
    .m_is_trade(m_is_trade),
    .m_is_reference(m_is_reference),
    .m_is_drop(m_is_drop),
    .m_error_corrupt(m_error_corrupt),
    .m_payload(m_payload),
    .m_msg_len(m_msg_len),
    .m_event_code(m_event_code),
    .m_ref_value(m_ref_value),
    .status_msg_count(status_msg_count),
    .status_byte_count(status_byte_count),
    .status_corrupt_count(status_corrupt_count),
    .status_frame_count(status_frame_count),
    .status_beat_count(status_beat_count),
    .status_last_pulse(status_last_pulse)
  );

  // --------------------------------------------------------------------------
  // Assumptions
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) assume(!s_axis_tvalid);
  end

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  function automatic bit is_trade_type(input [7:0] t);
    case (t)
      `MSG_ADD_ORDER, `MSG_ADD_ORDER_MPID, `MSG_ORDER_EXECUTED,
      `MSG_ORDER_EXECUTED_PRICE, `MSG_ORDER_CANCEL, `MSG_ORDER_DELETE,
      `MSG_ORDER_REPLACE, `MSG_TRADE_NON_CROSS, `MSG_CROSS_TRADE: is_trade_type = 1'b1;
      default: is_trade_type = 1'b0;
    endcase
  endfunction

  function automatic bit is_reference_type(input [7:0] t);
    case (t)
      `MSG_SYSTEM_EVENT, `MSG_STOCK_DIRECTORY, `MSG_STOCK_TRADING_ACTION,
      `MSG_REG_SHO_RESTRICTION, `MSG_MARKET_PARTICIPANT_POS, `MSG_MWCB_DECLINE_LEVEL,
      `MSG_MWCB_STATUS, `MSG_QUOTING_PERIOD_UPDATE, `MSG_LULD_AUCTION_COLLAR,
      `MSG_OPERATIONAL_HALT, `MSG_BROKEN_TRADE, `MSG_NOII, `MSG_RPII: is_reference_type = 1'b1;
      default: is_reference_type = 1'b0;
    endcase
  endfunction

  function automatic bit legal_len(input [7:0] t, input [7:0] l);
    case (t)
      `MSG_SYSTEM_EVENT:       legal_len = (l == `LEN_MSG_S);
      `MSG_STOCK_DIRECTORY:    legal_len = (l == `LEN_MSG_R);
      `MSG_STOCK_TRADING_ACTION: legal_len = (l == `LEN_MSG_H);
      `MSG_REG_SHO_RESTRICTION:  legal_len = (l == `LEN_MSG_Y);
      `MSG_MARKET_PARTICIPANT_POS: legal_len = (l == `LEN_MSG_L);
      `MSG_MWCB_DECLINE_LEVEL: legal_len = (l == `LEN_MSG_V);
      `MSG_MWCB_STATUS:        legal_len = (l == `LEN_MSG_W);
      `MSG_QUOTING_PERIOD_UPDATE: legal_len = (l == `LEN_MSG_K);
      `MSG_LULD_AUCTION_COLLAR: legal_len = (l == `LEN_MSG_J);
      `MSG_OPERATIONAL_HALT:   legal_len = (l == `LEN_MSG_h);
      `MSG_ADD_ORDER:          legal_len = (l == `LEN_MSG_A);
      `MSG_ADD_ORDER_MPID:     legal_len = (l == `LEN_MSG_F);
      `MSG_ORDER_EXECUTED:     legal_len = (l == `LEN_MSG_E);
      `MSG_ORDER_EXECUTED_PRICE: legal_len = (l == `LEN_MSG_C);
      `MSG_ORDER_CANCEL:       legal_len = (l == `LEN_MSG_X);
      `MSG_ORDER_DELETE:       legal_len = (l == `LEN_MSG_D);
      `MSG_ORDER_REPLACE:      legal_len = (l == `LEN_MSG_U);
      `MSG_TRADE_NON_CROSS:    legal_len = (l == `LEN_MSG_P);
      `MSG_CROSS_TRADE:        legal_len = (l == `LEN_MSG_Q);
      `MSG_BROKEN_TRADE:       legal_len = (l == `LEN_MSG_B);
      `MSG_NOII:               legal_len = (l == `LEN_MSG_I);
      `MSG_RPII:               legal_len = (l == `LEN_MSG_N);
      default:                 legal_len = 1'b0;
    endcase
  endfunction

  // --------------------------------------------------------------------------
  // Invariant 1: pre-trigger is the real decoded locate and is gated
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && raw_pre_valid) begin
      assert(raw_locate_pre == raw_order_data[475:460]);
    end
  end

  // --------------------------------------------------------------------------
  // Invariant 2: registered field equivalence (1 cycle after raw)
  // --------------------------------------------------------------------------
  reg          p_valid;
  reg  [7:0]   p_type;
  reg  [15:0]  p_locate, p_track;
  reg  [47:0]  p_ts;
  reg  [63:0]  p_ref, p_nref, p_shares, p_stock, p_match;
  reg  [31:0]  p_price, p_mpid, p_ref_value;
  reg  [7:0]   p_side, p_len;
  reg          p_printable, p_trade, p_ref_flag, p_corrupt;

  always @(posedge clk) begin
    if (!rst_n) begin
      p_valid <= 1'b0; p_type <= 0; p_locate <= 0; p_track <= 0; p_ts <= 0;
      p_ref <= 0; p_nref <= 0; p_shares <= 0; p_stock <= 0; p_match <= 0;
      p_price <= 0; p_mpid <= 0; p_side <= 0; p_printable <= 0;
      p_trade <= 0; p_ref_flag <= 0; p_corrupt <= 0; p_len <= 0;
    end else begin
      p_valid   <= raw_order_valid;
      p_type    <= raw_order_data[483:476];
      p_locate  <= raw_order_data[475:460];
      p_track   <= raw_order_data[459:444];
      p_ts      <= raw_order_data[443:396];
      p_ref     <= raw_order_data[395:332];
      p_nref    <= raw_order_data[331:268];
      p_side    <= raw_order_data[267:260];
      p_shares  <= raw_order_data[259:196];
      p_stock   <= raw_order_data[195:132];
      p_price   <= raw_order_data[131:100];
      p_match   <= raw_order_data[99:36];
      p_mpid    <= raw_order_data[35:4];
      p_printable <= raw_order_data[3];
      p_trade   <= raw_order_data[2];
      p_ref_flag<= raw_order_data[1];
      p_corrupt <= raw_order_data[0];
      p_len     <= raw_msg_length;
    end
  end

  always @(posedge clk) begin
    if (rst_n && p_valid) begin
      assert(m_axis_order_valid == p_valid);
      assert(m_order_type       == p_type);
      assert(m_stock_locate     == p_locate);
      assert(m_tracking_number  == p_track);
      assert(m_timestamp        == p_ts);
      assert(m_order_ref_num    == p_ref);
      assert(m_new_order_ref_num== p_nref);
      assert(m_side             == p_side);
      assert(m_shares           == p_shares);
      assert(m_stock            == p_stock);
      assert(m_price            == p_price);
      assert(m_match_number     == p_match);
      assert(m_mpid             == p_mpid);
      assert(m_printable        == p_printable);
      assert(m_is_trade         == p_trade);
      assert(m_is_reference     == p_ref_flag);
      assert(m_error_corrupt    == p_corrupt);
      assert(m_msg_len          == p_len);
    end
  end

  // --------------------------------------------------------------------------
  // Invariant 3: exactly one semantic class
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && m_axis_order_valid) begin
      assert((m_is_trade + m_is_reference + m_error_corrupt) == 1'b1);
    end
  end

  // --------------------------------------------------------------------------
  // Invariant 4: class matches opcode; corrupt has length 0
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && m_axis_order_valid) begin
      if (m_is_trade)
        assert(is_trade_type(m_order_type));
      if (m_is_reference)
        assert(is_reference_type(m_order_type));
      if (m_error_corrupt)
        assert(m_msg_len == 8'd0);
      else
        assert(legal_len(m_order_type, m_msg_len));
    end
  end

  // --------------------------------------------------------------------------
  // Invariant 5: flow control / no deadlock at the buffer threshold
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && status_buf_count <= 8'd112)
      assert(s_axis_tready == 1'b1);
  end

  // --------------------------------------------------------------------------
  // Covers
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      cover(m_axis_order_valid && (m_order_type == `MSG_ADD_ORDER));
      cover(m_axis_order_valid && (m_order_type == `MSG_ORDER_EXECUTED));
      cover(m_axis_order_valid && (m_order_type == `MSG_STOCK_DIRECTORY));
      cover(m_axis_order_valid && m_is_trade);
      cover(m_axis_order_valid && m_is_reference);
      cover(m_axis_order_valid && m_error_corrupt);
      cover(raw_pre_valid);
    end
  end

endmodule
