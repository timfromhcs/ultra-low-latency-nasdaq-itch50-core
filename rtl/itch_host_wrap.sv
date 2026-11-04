// ============================================================================
// File: rtl/itch_host_wrap.sv
// Module: itch_host_wrap
// Description: Narrow physical wrapper around the ITCH-50 parser. Keeps the
//              128-bit AXI4-Stream ingress but replaces the ~1,100-pin debug
//              record bus with a 32-bit host register port, so the design can be
//              placed and routed (the full record bus causes pin congestion).
//
//   Host register map (word address, 32-bit):
//     0  status_msg_count
//     1  status_corrupt_count
//     2  {last_type[7:0], 8'b0, last_locate[15:0]}
//     3  last_price
//     4  last_shares[31:0]
//     5  last_shares[63:32]
//     6  last_ref[31:0]
//     7  last_ref[63:32]
//     8  {30'b0, last_corrupt, last_valid}   (sticky flags, cleared by reset)
//     9  status_byte_count
//    10  updates (messages accepted into the register file)
//
//   Reading is combinational; the host side is a slow management port. There is
//   no write port.
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_HOST_WRAP_SV
`define ITCH_HOST_WRAP_SV

`include "itch_pkg.sv"

module itch_host_wrap #(
  parameter DATA_WIDTH = 128
)(
  input  wire         clk,
  input  wire         rst_n,

  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [(DATA_WIDTH/8)-1:0]   s_axis_tkeep,
  input  wire         s_axis_tvalid,
  input  wire         s_axis_tlast,
  output wire         s_axis_tready,

  input  wire [4:0]   host_addr,
  output reg  [31:0]  host_rdata
);

  wire        msg_valid;
  wire [7:0]  msg_type;
  wire [15:0] msg_locate;
  wire [31:0] msg_price;
  wire [63:0] msg_shares;
  wire [63:0] msg_ref;
  wire        msg_corrupt;

  wire [31:0] status_msg_count;
  wire [31:0] status_byte_count;
  wire [31:0] status_corrupt_count;

  reg [7:0]  last_type;
  reg [15:0] last_locate;
  reg [31:0] last_price;
  reg [63:0] last_shares;
  reg [63:0] last_ref;
  reg        last_valid;
  reg        last_corrupt;
  reg [31:0] updates;

  /* verilator lint_off PINCONNECTEMPTY */
  ultra_low_latency_nasdaq_itch50_cutthrough #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_parse (
    .clk(clk),
    .rst_n(rst_n),
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
    .m_axis_order_valid(msg_valid),
    .m_order_type(msg_type),
    .m_stock_locate(msg_locate),
    .m_tracking_number(),
    .m_timestamp(),
    .m_order_ref_num(msg_ref),
    .m_new_order_ref_num(),
    .m_side(),
    .m_shares(msg_shares),
    .m_stock(),
    .m_price(msg_price),
    .m_match_number(),
    .m_mpid(),
    .m_printable(),
    .m_is_trade(),
    .m_is_reference(),
    .m_is_drop(),
    .m_error_corrupt(msg_corrupt),
    .m_payload(),
    .m_msg_len(),
    .m_event_code(),
    .m_ref_value(),
    .status_msg_count(status_msg_count),
    .status_byte_count(status_byte_count),
    .status_corrupt_count(status_corrupt_count),
    .status_frame_count(),
    .status_beat_count(),
    .status_last_pulse()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @(posedge clk) begin
    if (!rst_n) begin
      last_type <= 8'd0;
      last_locate <= 16'd0;
      last_price <= 32'd0;
      last_shares <= 64'd0;
      last_ref <= 64'd0;
      last_valid <= 1'b0;
      last_corrupt <= 1'b0;
      updates <= 32'd0;
    end else if (msg_valid) begin
      last_type <= msg_type;
      last_locate <= msg_locate;
      last_price <= msg_price;
      last_shares <= msg_shares;
      last_ref <= msg_ref;
      last_valid <= 1'b1;
      last_corrupt <= msg_corrupt;
      updates <= updates + 32'd1;
    end
  end

  always @(*) begin
    case (host_addr)
      5'd0: host_rdata = status_msg_count;
      5'd1: host_rdata = status_corrupt_count;
      5'd2: host_rdata = {last_type, 8'd0, last_locate};
      5'd3: host_rdata = last_price;
      5'd4: host_rdata = last_shares[31:0];
      5'd5: host_rdata = last_shares[63:32];
      5'd6: host_rdata = last_ref[31:0];
      5'd7: host_rdata = last_ref[63:32];
      5'd8: host_rdata = {30'd0, last_corrupt, last_valid};
      5'd9: host_rdata = status_byte_count;
      5'd10: host_rdata = updates;
      default: host_rdata = 32'd0;
    endcase
  end

endmodule

`endif
