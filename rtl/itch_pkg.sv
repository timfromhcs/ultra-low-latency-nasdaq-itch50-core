// ============================================================================
// File: rtl/itch_pkg.sv
// Module: itch_pkg (Definitions & Constants Header)
// Description: NASDAQ ITCH 5.0 Protocol Definitions, Opcodes, Lengths, Offsets.
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_PKG_SV
`define ITCH_PKG_SV

`define MSG_SYSTEM_EVENT           8'h53
`define MSG_STOCK_DIRECTORY        8'h52
`define MSG_STOCK_TRADING_ACTION   8'h48
`define MSG_REG_SHO_RESTRICTION    8'h59
`define MSG_MARKET_PARTICIPANT_POS 8'h4C
`define MSG_MWCB_DECLINE_LEVEL     8'h56
`define MSG_MWCB_STATUS            8'h57
`define MSG_QUOTING_PERIOD_UPDATE  8'h4B
`define MSG_LULD_AUCTION_COLLAR    8'h4A
`define MSG_OPERATIONAL_HALT       8'h68

`define MSG_ADD_ORDER              8'h41
`define MSG_ADD_ORDER_MPID         8'h46
`define MSG_ORDER_EXECUTED         8'h45
`define MSG_ORDER_EXECUTED_PRICE   8'h43
`define MSG_ORDER_CANCEL           8'h58
`define MSG_ORDER_DELETE           8'h44
`define MSG_ORDER_REPLACE          8'h55

`define MSG_TRADE_NON_CROSS        8'h50
`define MSG_CROSS_TRADE            8'h51
`define MSG_BROKEN_TRADE           8'h42
`define MSG_NOII                   8'h49
`define MSG_RPII                   8'h4E

`define SIDE_BUY                   8'h42
`define SIDE_SELL                  8'h53

`define LEN_MSG_S 8'd12
`define LEN_MSG_R 8'd39
`define LEN_MSG_H 8'd25
`define LEN_MSG_Y 8'd20
`define LEN_MSG_L 8'd26
`define LEN_MSG_V 8'd35
`define LEN_MSG_W 8'd12
`define LEN_MSG_K 8'd28
`define LEN_MSG_J 8'd35
`define LEN_MSG_h 8'd21

`define LEN_MSG_A 8'd36
`define LEN_MSG_F 8'd40
`define LEN_MSG_E 8'd31
`define LEN_MSG_C 8'd36
`define LEN_MSG_X 8'd23
`define LEN_MSG_D 8'd19
`define LEN_MSG_U 8'd35
`define LEN_MSG_P 8'd44
`define LEN_MSG_Q 8'd40
`define LEN_MSG_B 8'd19
`define LEN_MSG_I 8'd50
`define LEN_MSG_N 8'd20

`define MAX_MSG_BYTES 64
`define PARSED_ORDER_WIDTH 452

`endif