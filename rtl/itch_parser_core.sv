// ============================================================================
// File: rtl/itch_parser_core.sv
// Module: itch_parser_core
// Description: Speculative parallel ITCH 5.0 decoder.
//
//   * Decodes all 22 official ITCH 5.0 opcodes (9 order/trade + 13 reference).
//   * Keeps the full 512-bit payload, so no administrative information is lost.
//   * Extends shares to 64 bit ('Q' cross trades carry a 64-bit quantity).
//   * Exposes a *valid* Stock-Locate pre-trigger for downstream L3 prefetch.
//
//   The whole decode is combinational. itch_top registers it for a deterministic
//   one-cycle egress; the async bypass is valid in the same cycle as the window
//   (one clock after s_axis_tdata). See itch_shifter.sv for the latency budget.
// ============================================================================
`ifndef ITCH_PARSER_CORE_SV
`define ITCH_PARSER_CORE_SV

`include "itch_pkg.sv"
`include "itch_drop_gate.sv"

module itch_parser_core (
  input  wire [511:0] window_data,
  input  wire [7:0]   window_valid_bytes,
  input  wire         enable_parser,

  output reg  [7:0]   parsed_msg_type,
  output reg  [15:0]  parsed_stock_locate,
  output reg  [15:0]  parsed_tracking_number,
  output reg  [47:0]  parsed_timestamp,
  output reg  [63:0]  parsed_order_ref_num,
  output reg  [63:0]  parsed_new_order_ref_num,
  output reg  [7:0]   parsed_side,
  output reg  [63:0]  parsed_shares,
  output reg  [63:0]  parsed_stock,
  output reg  [31:0]  parsed_price,
  output reg  [63:0]  parsed_match_number,
  output reg  [31:0]  parsed_mpid,
  output reg          parsed_printable,
  output reg          parsed_is_trade,
  output reg          parsed_is_reference,
  output reg          parsed_error_corrupt,

  // Full message preservation + generic decoded side-channel
  output reg  [511:0] parsed_payload,
  output reg  [7:0]   parsed_msg_length,
  output reg  [7:0]   parsed_event_code,
  output reg  [31:0]  parsed_ref_value,

  // Semantic class aliases (old interface compatibility)
  output wire         parsed_is_drop,

  // Early indicators
  output wire [15:0]  stock_locate_pre_trigger,
  output wire         pre_trigger_valid,
  output wire [7:0]   msg_length,
  output wire         msg_valid,
  output wire         is_trade_msg,
  output wire         is_reference_msg,
  output wire         is_drop_msg,
  output wire         is_corrupt_msg
);

  assign parsed_is_drop = parsed_is_reference;

  // --------------------------------------------------------------------------
  // Direct L3 pre-trigger (bytes 1..2, big-endian) with an explicit valid.
  // --------------------------------------------------------------------------
  assign stock_locate_pre_trigger = {window_data[15:8], window_data[23:16]};
  // A corrupt/unknown opcode must not trigger a downstream L3 prefetch.
  assign pre_trigger_valid        = enable_parser && (window_valid_bytes >= 8'd3) && !gate_is_corrupt;

  // --------------------------------------------------------------------------
  // Early opcode classifier / length decoder
  // --------------------------------------------------------------------------
  wire       gate_is_trade;
  wire       gate_is_reference;
  wire       gate_is_corrupt;
  wire [7:0] gate_len;
  /* verilator lint_off UNUSED */
  wire       gate_is_known;
  wire       gate_en;
  wire       gate_admin_drop;
  /* verilator lint_on UNUSED */

  itch_drop_gate u_drop_gate (
    .msg_type       (window_data[7:0]),
    .msg_valid      (enable_parser && (window_valid_bytes >= 8'd1)),
    .is_trade_order (gate_is_trade),
    .is_reference   (gate_is_reference),
    .is_corrupt     (gate_is_corrupt),
    .is_known       (gate_is_known),
    .msg_length     (gate_len),
    .gate_enable    (gate_en),
    .is_admin_drop  (gate_admin_drop)
  );

  assign msg_length        = gate_len;
  assign is_trade_msg      = gate_is_trade;
  assign is_reference_msg  = gate_is_reference;
  assign is_drop_msg       = gate_is_reference;
  assign is_corrupt_msg    = gate_is_corrupt;

  wire has_enough_bytes = (window_valid_bytes >= gate_len) && (gate_len > 8'd0);
  assign msg_valid = enable_parser &&
                     (has_enough_bytes ||
                      (gate_is_corrupt && (window_valid_bytes >= 8'd1)));

  // --------------------------------------------------------------------------
  // Common header slices (big-endian byte order, little-endian window)
  // --------------------------------------------------------------------------
  wire [7:0]  lead_type   = window_data[7:0];
  wire [15:0] comm_locate = {window_data[15:8],  window_data[23:16]};
  wire [15:0] comm_track  = {window_data[31:24], window_data[39:32]};
  wire [47:0] comm_ts     = {window_data[47:40], window_data[55:48], window_data[63:56],
                             window_data[71:64], window_data[79:72], window_data[87:80]};

  // Convenience byte slices
  wire [63:0] bytes_11_18 = {window_data[95:88],  window_data[103:96],  window_data[111:104], window_data[119:112],
                             window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
  wire [63:0] bytes_15_22 = {window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144],
                             window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]};
  wire [63:0] bytes_19_26 = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176],
                             window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208]};
  wire [63:0] bytes_24_31 = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                             window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
  wire [63:0] bytes_36_43 = {window_data[295:288], window_data[303:296], window_data[311:304], window_data[319:312],
                             window_data[327:320], window_data[335:328], window_data[343:336], window_data[351:344]};
  wire [31:0] bytes_11_14 = {window_data[95:88],  window_data[103:96],  window_data[111:104], window_data[119:112]};
  wire [31:0] bytes_32_35 = {window_data[263:256], window_data[271:264], window_data[279:272], window_data[287:280]};
  wire [31:0] bytes_36_39 = {window_data[295:288], window_data[303:296], window_data[311:304], window_data[319:312]};
  wire [31:0] bytes_20_23 = {window_data[167:160], window_data[175:168], window_data[183:176], window_data[191:184]};
  wire [31:0] bytes_21_24 = {window_data[175:168], window_data[183:176], window_data[191:184], window_data[199:192]};
  wire [31:0] bytes_27_30 = {window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]};

  // --------------------------------------------------------------------------
  // Speculative parallel decode
  // --------------------------------------------------------------------------
  always @(*) begin
    if (!enable_parser || !msg_valid) begin
      parsed_msg_type          = 8'd0;
      parsed_stock_locate      = 16'd0;
      parsed_tracking_number   = 16'd0;
      parsed_timestamp         = 48'd0;
      parsed_order_ref_num     = 64'd0;
      parsed_new_order_ref_num = 64'd0;
      parsed_side              = 8'd0;
      parsed_shares            = 64'd0;
      parsed_stock             = 64'd0;
      parsed_price             = 32'd0;
      parsed_match_number      = 64'd0;
      parsed_mpid              = 32'd0;
      parsed_printable         = 1'b0;
      parsed_is_trade          = 1'b0;
      parsed_is_reference      = 1'b0;
      parsed_error_corrupt     = 1'b0;
      parsed_payload           = 512'd0;
      parsed_msg_length        = 8'd0;
      parsed_event_code        = 8'd0;
      parsed_ref_value         = 32'd0;
    end else begin
      parsed_msg_type          = lead_type;
      parsed_stock_locate      = comm_locate;
      parsed_tracking_number   = comm_track;
      parsed_timestamp         = comm_ts;
      parsed_order_ref_num     = 64'd0;
      parsed_new_order_ref_num = 64'd0;
      parsed_side              = 8'd0;
      parsed_shares            = 64'd0;
      parsed_stock             = 64'd0;
      parsed_price             = 32'd0;
      parsed_match_number      = 64'd0;
      parsed_mpid              = 32'd0;
      parsed_printable         = 1'b0;
      parsed_is_trade          = gate_is_trade;
      parsed_is_reference      = gate_is_reference;
      parsed_error_corrupt     = gate_is_corrupt;
      parsed_payload           = window_data;
      parsed_msg_length        = gate_len;
      parsed_event_code        = 8'd0;
      parsed_ref_value         = 32'd0;

      case (lead_type)
        // ---------------- Order / trade messages ---------------------------
        `MSG_ADD_ORDER: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_side          = window_data[159:152];
          parsed_shares        = {32'd0, bytes_20_23};
          parsed_stock         = bytes_24_31;
          parsed_price         = bytes_32_35;
        end

        `MSG_ADD_ORDER_MPID: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_side          = window_data[159:152];
          parsed_shares        = {32'd0, bytes_20_23};
          parsed_stock         = bytes_24_31;
          parsed_price         = bytes_32_35;
          parsed_mpid          = bytes_36_39;
        end

        `MSG_ORDER_EXECUTED: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_shares        = {32'd0, {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]}};
          parsed_match_number  = {window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208],
                                  window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]};
        end

        `MSG_ORDER_EXECUTED_PRICE: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_shares        = {32'd0, {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]}};
          parsed_printable     = (window_data[191:184] == 8'h59); // 'Y'
          parsed_match_number  = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                                  window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
          parsed_price         = bytes_32_35;
        end

        `MSG_ORDER_CANCEL: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_shares        = {32'd0, {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]}};
        end

        `MSG_ORDER_DELETE: begin
          parsed_order_ref_num = bytes_11_18;
        end

        `MSG_ORDER_REPLACE: begin
          parsed_order_ref_num     = bytes_11_18;
          parsed_new_order_ref_num = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176],
                                      window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208]};
          parsed_shares            = {32'd0, {window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]}};
          parsed_price             = {window_data[255:248], window_data[263:256], window_data[271:264], window_data[279:272]};
        end

        `MSG_TRADE_NON_CROSS: begin
          parsed_order_ref_num = bytes_11_18;
          parsed_side          = window_data[159:152];
          parsed_shares        = {32'd0, bytes_20_23};
          parsed_stock         = bytes_24_31;
          parsed_price         = bytes_32_35;
          parsed_match_number  = bytes_36_43;
        end

        `MSG_CROSS_TRADE: begin
          parsed_shares        = bytes_11_18; // full 64-bit cross quantity
          parsed_stock         = bytes_19_26;
          parsed_price         = bytes_27_30;
          parsed_match_number  = {window_data[255:248], window_data[263:256], window_data[271:264], window_data[279:272],
                                  window_data[287:280], window_data[295:288], window_data[303:296], window_data[311:304]};
          parsed_event_code    = window_data[319:312]; // cross type
        end

        // ---------------- Reference / administrative ------------------------
        `MSG_SYSTEM_EVENT: begin
          parsed_event_code = window_data[95:88]; // event code at byte 11
        end

        `MSG_STOCK_DIRECTORY: begin
          parsed_stock      = bytes_11_18;        // 8-char symbol
          parsed_event_code = window_data[159:152]; // market category
          parsed_ref_value  = bytes_21_24;        // round lot size
        end

        `MSG_STOCK_TRADING_ACTION: begin
          parsed_stock      = bytes_11_18;
          parsed_event_code = window_data[159:152]; // trading state
          parsed_ref_value  = bytes_21_24;          // reason
        end

        `MSG_REG_SHO_RESTRICTION: begin
          parsed_stock      = bytes_11_18;
          parsed_event_code = window_data[159:152]; // reg SHO action
        end

        `MSG_MARKET_PARTICIPANT_POS: begin
          parsed_mpid       = bytes_11_14;          // MPID at bytes 11..14
          parsed_stock      = bytes_15_22;          // symbol at bytes 15..22
          parsed_event_code = window_data[207:200]; // participant state at byte 25
        end

        `MSG_OPERATIONAL_HALT: begin
          parsed_stock      = bytes_11_18;
          parsed_event_code = window_data[167:160]; // halt action at byte 20
        end

        `MSG_MWCB_DECLINE_LEVEL: begin
          parsed_ref_value  = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112]};
        end

        `MSG_MWCB_STATUS: begin
          parsed_event_code = window_data[95:88]; // breach level at byte 11
        end

        `MSG_QUOTING_PERIOD_UPDATE: begin
          parsed_stock      = bytes_11_18;
          parsed_event_code = window_data[159:152]; // quoting period start/end
        end

        `MSG_LULD_AUCTION_COLLAR: begin
          parsed_stock      = bytes_11_18;
        end

        `MSG_BROKEN_TRADE: begin
          parsed_match_number = bytes_11_18;
        end

        `MSG_NOII: begin
          parsed_stock      = bytes_11_18;
        end

        `MSG_RPII: begin
          parsed_stock      = bytes_11_18;
          parsed_side       = window_data[159:152]; // interest flag
        end

        default: begin
          // Unknown opcode: one-byte resync record.
          parsed_error_corrupt = 1'b1;
          parsed_is_trade     = 1'b0;
          parsed_is_reference  = 1'b0;
          parsed_msg_length    = 8'd0;
        end
      endcase

      // A corrupt frame must not leak bytes from the following message into
      // the common header fields. Keep only the offending opcode + payload.
      if (parsed_error_corrupt) begin
        parsed_stock_locate    = 16'd0;
        parsed_tracking_number = 16'd0;
        parsed_timestamp       = 48'd0;
      end
    end
  end

endmodule

`endif
