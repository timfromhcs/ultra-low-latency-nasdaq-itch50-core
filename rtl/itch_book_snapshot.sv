// ============================================================================
// File: rtl/itch_book_snapshot.sv
// Module: itch_book_snapshot
// Description: Per-locate snapshot table for a host read port. Latches the
//              latest top-of-book, last trade, volume and top-4 depth for each
//              stock locate so a host can read the current book state without
//              replaying the event stream.
//
//   Update: 1 event/clock from itch_top_of_book's m_* outputs.
//   Read:   present rd_locate with rd_valid; the snapshot appears one clock
//           later with snap_valid and stays stable until the next read.
//
//   Cost: LOCATES * (2 * DEPTH * (32 + 64) + 3 * 96 + 64) bits of state.
//   At 16 locates and depth 4 this is ~18 Kbit (about 18 K flip-flops), so use
//   it at the host bridge, not in the feed-path critical loop.
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_BOOK_SNAPSHOT_SV
`define ITCH_BOOK_SNAPSHOT_SV

module itch_book_snapshot #(
  parameter LOCATES = 16,
  parameter LOC_AW  = (LOCATES <= 1) ? 1 : $clog2(LOCATES)
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // Update port (from the book's per-message output).
  input  wire                        upd_valid,
  input  wire [LOC_AW-1:0]           upd_locate,
  input  wire [31:0]                 upd_bid_price,
  input  wire [63:0]                 upd_bid_shares,
  input  wire [31:0]                 upd_ask_price,
  input  wire [63:0]                 upd_ask_shares,
  input  wire [31:0]                 upd_last_price,
  input  wire [63:0]                 upd_last_shares,
  input  wire [63:0]                 upd_volume,
  input  wire [31:0]                 upd_bid_p0, upd_bid_p1, upd_bid_p2, upd_bid_p3,
  input  wire [63:0]                 upd_bid_s0, upd_bid_s1, upd_bid_s2, upd_bid_s3,
  input  wire [31:0]                 upd_ask_p0, upd_ask_p1, upd_ask_p2, upd_ask_p3,
  input  wire [63:0]                 upd_ask_s0, upd_ask_s1, upd_ask_s2, upd_ask_s3,

  // Host read port.
  input  wire                        rd_valid,
  input  wire [LOC_AW-1:0]           rd_locate,
  output reg                         snap_valid,
  output reg  [15:0]                 snap_locate,
  output reg                         snap_hit,
  output reg  [31:0]                 snap_bid_price,
  output reg  [63:0]                 snap_bid_shares,
  output reg  [31:0]                 snap_ask_price,
  output reg  [63:0]                 snap_ask_shares,
  output reg  [31:0]                 snap_last_price,
  output reg  [63:0]                 snap_last_shares,
  output reg  [63:0]                 snap_volume,
  output reg  [31:0]                 snap_bid_p0, snap_bid_p1, snap_bid_p2, snap_bid_p3,
  output reg  [63:0]                 snap_bid_s0, snap_bid_s1, snap_bid_s2, snap_bid_s3,
  output reg  [31:0]                 snap_ask_p0, snap_ask_p1, snap_ask_p2, snap_ask_p3,
  output reg  [63:0]                 snap_ask_s0, snap_ask_s1, snap_ask_s2, snap_ask_s3,
  output reg  [31:0]                 updates
);

  localparam DEPTH = 4;
  localparam N = LOCATES * DEPTH;

  reg        hit    [0:LOCATES-1];
  reg [31:0] bidp   [0:LOCATES-1];
  reg [63:0] bids   [0:LOCATES-1];
  reg [31:0] askp   [0:LOCATES-1];
  reg [63:0] asks   [0:LOCATES-1];
  reg [31:0] lastp  [0:LOCATES-1];
  reg [63:0] lasts  [0:LOCATES-1];
  reg [63:0] vol    [0:LOCATES-1];

  reg [31:0] dbp [0:N-1];
  reg [63:0] dbs [0:N-1];
  reg [31:0] dap [0:N-1];
  reg [63:0] das [0:N-1];

  wire [LOC_AW-1:0] upd_idx = upd_locate;
  wire [LOC_AW-1:0] rd_idx  = rd_locate;

  integer i;

  always @(posedge clk) begin
    if (!rst_n) begin
      updates <= 32'd0;
      snap_valid <= 1'b0;
      snap_locate <= 16'd0;
      snap_hit <= 1'b0;
      snap_bid_price <= 32'd0;
      snap_bid_shares <= 64'd0;
      snap_ask_price <= 32'd0;
      snap_ask_shares <= 64'd0;
      snap_last_price <= 32'd0;
      snap_last_shares <= 64'd0;
      snap_volume <= 64'd0;
      snap_bid_p0 <= 0; snap_bid_p1 <= 0; snap_bid_p2 <= 0; snap_bid_p3 <= 0;
      snap_bid_s0 <= 0; snap_bid_s1 <= 0; snap_bid_s2 <= 0; snap_bid_s3 <= 0;
      snap_ask_p0 <= 0; snap_ask_p1 <= 0; snap_ask_p2 <= 0; snap_ask_p3 <= 0;
      snap_ask_s0 <= 0; snap_ask_s1 <= 0; snap_ask_s2 <= 0; snap_ask_s3 <= 0;
      for (i = 0; i < LOCATES; i = i + 1) begin
        hit[i] <= 1'b0;
        bidp[i] <= 32'd0; bids[i] <= 64'd0;
        askp[i] <= 32'd0; asks[i] <= 64'd0;
        lastp[i] <= 32'd0; lasts[i] <= 64'd0;
        vol[i] <= 64'd0;
      end
      for (i = 0; i < N; i = i + 1) begin
        dbp[i] <= 32'd0; dbs[i] <= 64'd0;
        dap[i] <= 32'd0; das[i] <= 64'd0;
      end
    end else begin
      snap_valid <= rd_valid;

      if (upd_valid) begin
        hit[upd_idx]  <= 1'b1;
        bidp[upd_idx] <= upd_bid_price;
        bids[upd_idx] <= upd_bid_shares;
        askp[upd_idx] <= upd_ask_price;
        asks[upd_idx] <= upd_ask_shares;
        lastp[upd_idx] <= upd_last_price;
        lasts[upd_idx] <= upd_last_shares;
        vol[upd_idx]  <= upd_volume;
        dbp[upd_idx*DEPTH+0] <= upd_bid_p0; dbs[upd_idx*DEPTH+0] <= upd_bid_s0;
        dbp[upd_idx*DEPTH+1] <= upd_bid_p1; dbs[upd_idx*DEPTH+1] <= upd_bid_s1;
        dbp[upd_idx*DEPTH+2] <= upd_bid_p2; dbs[upd_idx*DEPTH+2] <= upd_bid_s2;
        dbp[upd_idx*DEPTH+3] <= upd_bid_p3; dbs[upd_idx*DEPTH+3] <= upd_bid_s3;
        dap[upd_idx*DEPTH+0] <= upd_ask_p0; das[upd_idx*DEPTH+0] <= upd_ask_s0;
        dap[upd_idx*DEPTH+1] <= upd_ask_p1; das[upd_idx*DEPTH+1] <= upd_ask_s1;
        dap[upd_idx*DEPTH+2] <= upd_ask_p2; das[upd_idx*DEPTH+2] <= upd_ask_s2;
        dap[upd_idx*DEPTH+3] <= upd_ask_p3; das[upd_idx*DEPTH+3] <= upd_ask_s3;
        updates <= updates + 32'd1;
      end

      if (rd_valid) begin
        snap_locate     <= {{(16-LOC_AW){1'b0}}, rd_idx};
        snap_hit        <= hit[rd_idx];
        snap_bid_price  <= bidp[rd_idx];
        snap_bid_shares <= bids[rd_idx];
        snap_ask_price  <= askp[rd_idx];
        snap_ask_shares <= asks[rd_idx];
        snap_last_price <= lastp[rd_idx];
        snap_last_shares<= lasts[rd_idx];
        snap_volume     <= vol[rd_idx];
        snap_bid_p0 <= dbp[rd_idx*DEPTH+0]; snap_bid_s0 <= dbs[rd_idx*DEPTH+0];
        snap_bid_p1 <= dbp[rd_idx*DEPTH+1]; snap_bid_s1 <= dbs[rd_idx*DEPTH+1];
        snap_bid_p2 <= dbp[rd_idx*DEPTH+2]; snap_bid_s2 <= dbs[rd_idx*DEPTH+2];
        snap_bid_p3 <= dbp[rd_idx*DEPTH+3]; snap_bid_s3 <= dbs[rd_idx*DEPTH+3];
        snap_ask_p0 <= dap[rd_idx*DEPTH+0]; snap_ask_s0 <= das[rd_idx*DEPTH+0];
        snap_ask_p1 <= dap[rd_idx*DEPTH+1]; snap_ask_s1 <= das[rd_idx*DEPTH+1];
        snap_ask_p2 <= dap[rd_idx*DEPTH+2]; snap_ask_s2 <= das[rd_idx*DEPTH+2];
        snap_ask_p3 <= dap[rd_idx*DEPTH+3]; snap_ask_s3 <= das[rd_idx*DEPTH+3];
      end
    end
  end

endmodule

`endif
