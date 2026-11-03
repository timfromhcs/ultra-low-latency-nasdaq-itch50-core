// ============================================================================
// File: rtl/itch_drop_gate.sv
// Module: itch_drop_gate
// Description: Combinational opcode classifier and length decoder.
//
//   The original design called every non-trading message a "drop" and threw
//   its payload away. That loses Stock Directory (symbol mapping), trading
//   state, LULD/MWCB state and broken-trade information. This version keeps
//   two independent classifications:
//     * is_trade_order : affects the order book / trade tape
//     * is_reference   : reference-data / administrative, still useful
//     * is_corrupt     : unknown opcode, consume 1 byte and resynchronise
// ============================================================================
`ifndef ITCH_DROP_GATE_SV
`define ITCH_DROP_GATE_SV

`include "itch_pkg.sv"

module itch_drop_gate (
  input  wire [7:0]   msg_type,
  input  wire         msg_valid,
  output reg          is_trade_order,
  output reg          is_reference,
  output reg          is_corrupt,
  output reg          is_known,
  output reg  [7:0]   msg_length,
  output reg          gate_enable,
  // Backwards-compatible alias for downstream users of the old interface.
  output wire         is_admin_drop
);

  assign is_admin_drop = is_reference;

  always @(*) begin
    if (!msg_valid) begin
      is_trade_order = 1'b0;
      is_reference   = 1'b0;
      is_corrupt     = 1'b0;
      is_known       = 1'b0;
      msg_length     = 8'd0;
      gate_enable    = 1'b0;
    end else begin
      is_trade_order = 1'b0;
      is_reference   = 1'b0;
      is_corrupt     = 1'b0;
      is_known       = 1'b1;
      gate_enable    = 1'b1;
      case (msg_type)
        // ----- order / trade path -----------------------------------------
        `MSG_ADD_ORDER: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_A;
        end
        `MSG_ADD_ORDER_MPID: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_F;
        end
        `MSG_ORDER_EXECUTED: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_E;
        end
        `MSG_ORDER_EXECUTED_PRICE: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_C;
        end
        `MSG_ORDER_CANCEL: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_X;
        end
        `MSG_ORDER_DELETE: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_D;
        end
        `MSG_ORDER_REPLACE: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_U;
        end
        `MSG_TRADE_NON_CROSS: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_P;
        end
        `MSG_CROSS_TRADE: begin
          is_trade_order = 1'b1; msg_length = `LEN_MSG_Q;
        end

        // ----- reference / administrative path ----------------------------
        `MSG_SYSTEM_EVENT: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_S;
        end
        `MSG_STOCK_DIRECTORY: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_R;
        end
        `MSG_STOCK_TRADING_ACTION: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_H;
        end
        `MSG_REG_SHO_RESTRICTION: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_Y;
        end
        `MSG_MARKET_PARTICIPANT_POS: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_L;
        end
        `MSG_MWCB_DECLINE_LEVEL: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_V;
        end
        `MSG_MWCB_STATUS: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_W;
        end
        `MSG_QUOTING_PERIOD_UPDATE: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_K;
        end
        `MSG_LULD_AUCTION_COLLAR: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_J;
        end
        `MSG_OPERATIONAL_HALT: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_h;
        end
        `MSG_BROKEN_TRADE: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_B;
        end
        `MSG_NOII: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_I;
        end
        `MSG_RPII: begin
          is_reference = 1'b1; msg_length = `LEN_MSG_N;
        end

        default: begin
          is_trade_order = 1'b0;
          is_reference   = 1'b0;
          is_corrupt     = 1'b1;
          is_known       = 1'b0;
          msg_length     = 8'd0;
          gate_enable    = 1'b0;
        end
      endcase
    end
  end

endmodule

`endif
