// ============================================================================
// File: rtl/itch_book_snapshot_top.sv
// Module: itch_book_snapshot_top
// Description: Integration wrapper: parser + top-of-book + per-locate snapshot.
//              Exposes the AXI4-Stream ingress and the snapshot read port so a
//              host can read the book state after feeding events.
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_BOOK_SNAPSHOT_TOP_SV
`define ITCH_BOOK_SNAPSHOT_TOP_SV

module itch_book_snapshot_top #(
  parameter DATA_WIDTH = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [(DATA_WIDTH/8)-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  input  wire                        rd_valid,
  input  wire [3:0]                  rd_locate,
  output wire                        snap_valid,
  output wire [15:0]                 snap_locate,
  output wire                        snap_hit,
  output wire [31:0]                 snap_bid_price,
  output wire [63:0]                 snap_bid_shares,
  output wire [31:0]                 snap_ask_price,
  output wire [63:0]                 snap_ask_shares,
  output wire [31:0]                 snap_last_price,
  output wire [63:0]                 snap_last_shares,
  output wire [63:0]                 snap_volume,
  output wire [31:0]                 snap_bid_p0, snap_bid_p1, snap_bid_p2, snap_bid_p3,
  output wire [63:0]                 snap_bid_s0, snap_bid_s1, snap_bid_s2, snap_bid_s3,
  output wire [31:0]                 snap_ask_p0, snap_ask_p1, snap_ask_p2, snap_ask_p3,
  output wire [63:0]                 snap_ask_s0, snap_ask_s1, snap_ask_s2, snap_ask_s3,
  output wire [31:0]                 snap_updates,
  output wire                        ready
);

  wire bbo_valid;
  wire [15:0] bbo_locate;
  wire [31:0] bbo_bid_price, bbo_ask_price, bbo_last_price;
  wire [63:0] bbo_bid_shares, bbo_ask_shares, bbo_last_shares, bbo_volume;
  wire [31:0] bbo_bid_p0, bbo_bid_p1, bbo_bid_p2, bbo_bid_p3;
  wire [63:0] bbo_bid_s0, bbo_bid_s1, bbo_bid_s2, bbo_bid_s3;
  wire [31:0] bbo_ask_p0, bbo_ask_p1, bbo_ask_p2, bbo_ask_p3;
  wire [63:0] bbo_ask_s0, bbo_ask_s1, bbo_ask_s2, bbo_ask_s3;

  /* verilator lint_off PINCONNECTEMPTY */
  itch_top_book #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_book (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .bbo_valid(bbo_valid),
    .bbo_locate(bbo_locate),
    .bbo_bid_price(bbo_bid_price),
    .bbo_bid_shares(bbo_bid_shares),
    .bbo_ask_price(bbo_ask_price),
    .bbo_ask_shares(bbo_ask_shares),
    .bbo_last_price(bbo_last_price),
    .bbo_last_shares(bbo_last_shares),
    .bbo_volume(bbo_volume),
    .bbo_bid_p0(bbo_bid_p0), .bbo_bid_p1(bbo_bid_p1), .bbo_bid_p2(bbo_bid_p2), .bbo_bid_p3(bbo_bid_p3),
    .bbo_bid_s0(bbo_bid_s0), .bbo_bid_s1(bbo_bid_s1), .bbo_bid_s2(bbo_bid_s2), .bbo_bid_s3(bbo_bid_s3),
    .bbo_ask_p0(bbo_ask_p0), .bbo_ask_p1(bbo_ask_p1), .bbo_ask_p2(bbo_ask_p2), .bbo_ask_p3(bbo_ask_p3),
    .bbo_ask_s0(bbo_ask_s0), .bbo_ask_s1(bbo_ask_s1), .bbo_ask_s2(bbo_ask_s2), .bbo_ask_s3(bbo_ask_s3),
    .cfg_max_shares(64'd0),
    .cfg_collar(32'd0),
    .risk_rejects(),
    .status_msg_count(),
    .status_corrupt_count(),
    .metrics_msg_count(), .metrics_byte_count(), .metrics_gap_count(),
    .metrics_drop_count(), .metrics_cycle_count(), .metrics_occupancy_max(),
    .metrics_hist0(), .metrics_hist1(), .metrics_hist2(), .metrics_hist3(),
    .metrics_hist4(), .metrics_hist5(), .metrics_hist6(), .metrics_hist7(),
    .ready(ready)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // The snapshot indexes locates with LOC_AW bits; the upper bits are unused here.
  wire _unused = &{1'b0, bbo_locate[15:4]};

  itch_book_snapshot #(
    .LOCATES(16)
  ) u_snap (
    .clk(clk),
    .rst_n(rst_n),
    .upd_valid(bbo_valid),
    .upd_locate(bbo_locate[3:0]),
    .upd_bid_price(bbo_bid_price),
    .upd_bid_shares(bbo_bid_shares),
    .upd_ask_price(bbo_ask_price),
    .upd_ask_shares(bbo_ask_shares),
    .upd_last_price(bbo_last_price),
    .upd_last_shares(bbo_last_shares),
    .upd_volume(bbo_volume),
    .upd_bid_p0(bbo_bid_p0), .upd_bid_p1(bbo_bid_p1), .upd_bid_p2(bbo_bid_p2), .upd_bid_p3(bbo_bid_p3),
    .upd_bid_s0(bbo_bid_s0), .upd_bid_s1(bbo_bid_s1), .upd_bid_s2(bbo_bid_s2), .upd_bid_s3(bbo_bid_s3),
    .upd_ask_p0(bbo_ask_p0), .upd_ask_p1(bbo_ask_p1), .upd_ask_p2(bbo_ask_p2), .upd_ask_p3(bbo_ask_p3),
    .upd_ask_s0(bbo_ask_s0), .upd_ask_s1(bbo_ask_s1), .upd_ask_s2(bbo_ask_s2), .upd_ask_s3(bbo_ask_s3),
    .rd_valid(rd_valid),
    .rd_locate(rd_locate),
    .snap_valid(snap_valid),
    .snap_locate(snap_locate),
    .snap_hit(snap_hit),
    .snap_bid_price(snap_bid_price),
    .snap_bid_shares(snap_bid_shares),
    .snap_ask_price(snap_ask_price),
    .snap_ask_shares(snap_ask_shares),
    .snap_last_price(snap_last_price),
    .snap_last_shares(snap_last_shares),
    .snap_volume(snap_volume),
    .snap_bid_p0(snap_bid_p0), .snap_bid_p1(snap_bid_p1), .snap_bid_p2(snap_bid_p2), .snap_bid_p3(snap_bid_p3),
    .snap_bid_s0(snap_bid_s0), .snap_bid_s1(snap_bid_s1), .snap_bid_s2(snap_bid_s2), .snap_bid_s3(snap_bid_s3),
    .snap_ask_p0(snap_ask_p0), .snap_ask_p1(snap_ask_p1), .snap_ask_p2(snap_ask_p2), .snap_ask_p3(snap_ask_p3),
    .snap_ask_s0(snap_ask_s0), .snap_ask_s1(snap_ask_s1), .snap_ask_s2(snap_ask_s2), .snap_ask_s3(snap_ask_s3),
    .updates(snap_updates)
  );

endmodule

`endif
