// ============================================================================
// File: rtl/mold_recovery.sv
// Module: mold_recovery
// Description: MoldUDP64 sequence tracking and retransmission request generator.
//
//   Accepts in-order frames and forwards an `accept` pulse. On a forward gap it
//   raises `req_valid` with the missing range (`req_seq`, `req_count`), which the
//   upstream feed is expected to replay. A replay that closes the gap clears the
//   request and counts as `recovered`. If the replay does not arrive within
//   TIMEOUT cycles, the block abandons the gap, resynchronises to the observed
//   sequence and pulses `abandon`.
//
//   Frames before `expected` are treated as duplicates and ignored. The block
//   does not buffer frames; the replay source is responsible for resending the
//   requested range (including the frame that revealed the gap).
// ============================================================================
`ifndef MOLD_RECOVERY_SV
`define MOLD_RECOVERY_SV

`include "itch_pkg.sv"

module mold_recovery #(
  parameter TIMEOUT = 256
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire [63:0]                 initial_seq,

  input  wire                        frame_valid,
  input  wire [63:0]                 frame_seq,
  input  wire [15:0]                 frame_count,

  output reg                         accept,
  output reg                         req_valid,
  output reg  [63:0]                 req_seq,
  output reg  [15:0]                 req_count,
  output reg                         abandon,

  output reg  [31:0]                 gaps,
  output reg  [31:0]                 recovered,
  output reg  [31:0]                 abandoned,
  output reg  [31:0]                 duplicates,
  output reg  [63:0]                 expected
);

  reg [63:0] pending_seq;
  reg [31:0] timeout;
  wire [63:0] gap_msgs = frame_seq - expected;

  always @(posedge clk) begin
    if (!rst_n) begin
      accept     <= 1'b0;
      abandon    <= 1'b0;
      req_valid  <= 1'b0;
      req_seq    <= 64'd0;
      req_count  <= 16'd0;
      pending_seq<= 64'd0;
      timeout    <= 32'd0;
      gaps       <= 32'd0;
      recovered  <= 32'd0;
      abandoned  <= 32'd0;
      duplicates <= 32'd0;
      expected   <= initial_seq;
    end else begin
      accept  <= 1'b0;
      abandon <= 1'b0;

      if (frame_valid) begin
        if (frame_seq == expected) begin
          accept   <= 1'b1;
          expected <= frame_seq + {48'd0, frame_count};
          timeout  <= 32'd0;
          if (req_valid) begin
            req_valid <= 1'b0;
            recovered <= recovered + 32'd1;
          end
        end else if (frame_seq > expected) begin
          if (!req_valid) begin
            req_valid  <= 1'b1;
            req_seq    <= expected;
            req_count  <= (gap_msgs > 64'd65535) ? 16'hFFFF : gap_msgs[15:0];
            pending_seq<= frame_seq;
            gaps       <= gaps + 32'd1;
            timeout    <= 32'd0;
          end
        end else begin
          duplicates <= duplicates + 32'd1;
        end
      end

      if (req_valid && !frame_valid) begin
        if (timeout >= TIMEOUT) begin
          req_valid <= 1'b0;
          abandon   <= 1'b1;
          expected  <= pending_seq;
          timeout   <= 32'd0;
          abandoned <= abandoned + 32'd1;
        end else begin
          timeout <= timeout + 32'd1;
        end
      end
    end
  end

endmodule

`endif
