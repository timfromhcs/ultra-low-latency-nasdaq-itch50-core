// ============================================================================
// File: rtl/itch_parser_core.sv
// Module: itch_parser_core
// Description: Speculative Parallel Parsing Matrix & Direct L3 Pre-Trigger.
// ============================================================================
`ifndef ITCH_PARSER_CORE_SV
`define ITCH_PARSER_CORE_SV

`include "itch_pkg.sv"
`include "itch_drop_gate.sv"

module itch_parser_core (
  /* verilator lint_off UNUSED */
  input  wire [511:0] window_data,
  /* verilator lint_on UNUSED */
  input  wire [7:0]   window_valid_bytes,
  input  wire         enable_parser,

  output reg  [7:0]   parsed_msg_type,
  output reg  [15:0]  parsed_stock_locate,
  output reg  [15:0]  parsed_tracking_number,
  output reg  [47:0]  parsed_timestamp,
  output reg  [63:0]  parsed_order_ref_num,
  output reg  [63:0]  parsed_new_order_ref_num,
  output reg  [7:0]   parsed_side,
  output reg  [31:0]  parsed_shares,
  output reg  [63:0]  parsed_stock,
  output reg  [31:0]  parsed_price,
  output reg  [63:0]  parsed_match_number,
  output reg  [31:0]  parsed_mpid,
  output reg          parsed_printable,
  output reg          parsed_is_trade,
  output reg          parsed_is_drop,
  output reg          parsed_error_corrupt,

  output wire [15:0]  stock_locate_pre_trigger,
  output wire [7:0]   msg_length,
  output wire         msg_valid,
  output wire         is_trade_msg,
  output wire         is_drop_msg,
  output wire         is_corrupt_msg
);

  // ------------------------------------------------------------------------
  // Direct L3 Pre-Trigger (< 0.3ns combinatorial propagation)
  // ------------------------------------------------------------------------
  assign stock_locate_pre_trigger = {window_data[15:8], window_data[23:16]};

  // ------------------------------------------------------------------------
  // Early Non-Trade Drop Gate
  // ------------------------------------------------------------------------
  wire       gate_is_trade;
  wire       gate_is_drop;
  wire       gate_is_corrupt;
  wire [7:0] gate_len;
  /* verilator lint_off UNUSED */
  wire       gate_en;
  /* verilator lint_on UNUSED */

  itch_drop_gate u_drop_gate (
    .msg_type      (window_data[7:0]),
    .msg_valid     (enable_parser && (window_valid_bytes >= 8'd1)),
    .is_trade_order(gate_is_trade),
    .is_admin_drop (gate_is_drop),
    .is_corrupt    (gate_is_corrupt),
    .msg_length    (gate_len),
    .gate_enable   (gate_en)
  );

  assign msg_length     = gate_len;
  assign is_trade_msg   = gate_is_trade;
  assign is_drop_msg    = gate_is_drop;
  assign is_corrupt_msg = gate_is_corrupt;

  wire has_enough_bytes = (window_valid_bytes >= gate_len) && (gate_len > 8'd0);
  assign msg_valid      = enable_parser && (has_enough_bytes || (gate_is_corrupt && (window_valid_bytes >= 8'd1)));

  // ------------------------------------------------------------------------
  // Common Header Slices
  // ------------------------------------------------------------------------
  wire [7:0]  lead_type   = window_data[7:0];
  wire [15:0] comm_locate = {window_data[15:8], window_data[23:16]};
  wire [15:0] comm_track  = {window_data[31:24], window_data[39:32]};
  wire [47:0] comm_ts     = {window_data[47:40], window_data[55:48], window_data[63:56],
                             window_data[71:64], window_data[79:72], window_data[87:80]};

  // ------------------------------------------------------------------------
  // Speculative Parallel Multiplexing Matrix
  // ------------------------------------------------------------------------
  always @(*) begin
    if (!enable_parser || !msg_valid) begin
      parsed_msg_type          = 8'd0;
      parsed_stock_locate      = 16'd0;
      parsed_tracking_number   = 16'd0;
      parsed_timestamp         = 48'd0;
      parsed_order_ref_num     = 64'd0;
      parsed_new_order_ref_num = 64'd0;
      parsed_side              = 8'd0;
      parsed_shares            = 32'd0;
      parsed_stock             = 64'd0;
      parsed_price             = 32'd0;
      parsed_match_number      = 64'd0;
      parsed_mpid              = 32'd0;
      parsed_printable         = 1'b0;
      parsed_is_trade          = 1'b0;
      parsed_is_drop           = 1'b0;
      parsed_error_corrupt     = 1'b0;
    end else begin
      parsed_msg_type          = lead_type;
      parsed_stock_locate      = comm_locate;
      parsed_tracking_number   = comm_track;
      parsed_timestamp         = comm_ts;
      parsed_order_ref_num     = 64'd0;
      parsed_new_order_ref_num = 64'd0;
      parsed_side              = 8'd0;
      parsed_shares            = 32'd0;
      parsed_stock             = 64'd0;
      parsed_price             = 32'd0;
      parsed_match_number      = 64'd0;
      parsed_mpid              = 32'd0;
      parsed_printable         = 1'b0;
      parsed_is_trade          = gate_is_trade;
      parsed_is_drop           = gate_is_drop;
      parsed_error_corrupt     = gate_is_corrupt;

      case (lead_type)
        `MSG_ADD_ORDER: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_side          = window_data[159:152];
          parsed_shares        = {window_data[167:160], window_data[175:168], window_data[183:176], window_data[191:184]};
          parsed_stock         = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                                  window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
          parsed_price         = {window_data[263:256], window_data[271:264], window_data[279:272], window_data[287:280]};
        end

        `MSG_ADD_ORDER_MPID: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_side          = window_data[159:152];
          parsed_shares        = {window_data[167:160], window_data[175:168], window_data[183:176], window_data[191:184]};
          parsed_stock         = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                                  window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
          parsed_price         = {window_data[263:256], window_data[271:264], window_data[279:272], window_data[287:280]};
          parsed_mpid          = {window_data[295:288], window_data[303:296], window_data[311:304], window_data[319:312]};
        end

        `MSG_ORDER_EXECUTED: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_shares        = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]};
          parsed_match_number  = {window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208],
                                  window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]};
        end

        `MSG_ORDER_EXECUTED_PRICE: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_shares        = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]};
          parsed_printable     = (window_data[191:184] == 8'h59);
          parsed_match_number  = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                                  window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
          parsed_price         = {window_data[263:256], window_data[271:264], window_data[279:272], window_data[287:280]};
        end

        `MSG_ORDER_CANCEL: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_shares        = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176]};
        end

        `MSG_ORDER_DELETE: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
        end

        `MSG_ORDER_REPLACE: begin
          parsed_order_ref_num     = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                      window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_new_order_ref_num = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176],
                                      window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208]};
          parsed_shares            = {window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]};
          parsed_price             = {window_data[255:248], window_data[263:256], window_data[271:264], window_data[279:272]};
        end

        `MSG_TRADE_NON_CROSS: begin
          parsed_order_ref_num = {window_data[95:88], window_data[103:96], window_data[111:104], window_data[119:112],
                                  window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_side          = window_data[159:152];
          parsed_shares        = {window_data[167:160], window_data[175:168], window_data[183:176], window_data[191:184]};
          parsed_stock         = {window_data[199:192], window_data[207:200], window_data[215:208], window_data[223:216],
                                  window_data[231:224], window_data[239:232], window_data[247:240], window_data[255:248]};
          parsed_price         = {window_data[263:256], window_data[271:264], window_data[279:272], window_data[287:280]};
          parsed_match_number  = {window_data[295:288], window_data[303:296], window_data[311:304], window_data[319:312],
                                  window_data[327:320], window_data[335:328], window_data[343:336], window_data[351:344]};
        end

        `MSG_CROSS_TRADE: begin
          parsed_shares        = {window_data[127:120], window_data[135:128], window_data[143:136], window_data[151:144]};
          parsed_stock         = {window_data[159:152], window_data[167:160], window_data[175:168], window_data[183:176],
                                  window_data[191:184], window_data[199:192], window_data[207:200], window_data[215:208]};
          parsed_price         = {window_data[223:216], window_data[231:224], window_data[239:232], window_data[247:240]};
          parsed_match_number  = {window_data[255:248], window_data[263:256], window_data[271:264], window_data[279:272],
                                  window_data[287:280], window_data[295:288], window_data[303:296], window_data[311:304]};
        end

        default: begin
        end
      endcase
    end
  end

endmodule

`endif