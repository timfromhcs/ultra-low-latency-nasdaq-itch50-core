// ============================================================================
// File: rtl/itch_metrics.sv
// Module: itch_metrics
// Description: Performance counters for the ITCH pipeline:
//   - message and byte totals
//   - gap / drop pulse counts
//   - maximum buffer occupancy
//   - inter-message gap histogram (cycles between messages)
//   - free-running cycle counter (the host derives messages/s from it)
//
//   The histogram bins are: 0 (back-to-back), 1, 2, 3, 4-7, 8-15, 16-31, 32+.
// ============================================================================
`ifndef ITCH_METRICS_SV
`define ITCH_METRICS_SV

`include "itch_pkg.sv"

module itch_metrics (
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire                        msg_valid,
  input  wire [7:0]                  msg_len,
  input  wire                        gap_pulse,
  input  wire                        drop_pulse,
  input  wire [7:0]                  occupancy,

  output reg  [31:0]                 msg_count,
  output reg  [31:0]                 byte_count,
  output reg  [31:0]                 gap_count,
  output reg  [31:0]                 drop_count,
  output reg  [31:0]                 cycle_count,
  output reg  [7:0]                  occupancy_max,
  output reg  [31:0]                 hist0,
  output reg  [31:0]                 hist1,
  output reg  [31:0]                 hist2,
  output reg  [31:0]                 hist3,
  output reg  [31:0]                 hist4,
  output reg  [31:0]                 hist5,
  output reg  [31:0]                 hist6,
  output reg  [31:0]                 hist7
);

  reg [31:0] since;

  // Saturating bin for the cycles since the previous message.
  wire [2:0] bin = (since == 32'd0) ? 3'd0 :
                   (since == 32'd1) ? 3'd1 :
                   (since == 32'd2) ? 3'd2 :
                   (since == 32'd3) ? 3'd3 :
                   (since <= 32'd7) ? 3'd4 :
                   (since <= 32'd15) ? 3'd5 :
                   (since <= 32'd31) ? 3'd6 : 3'd7;

  always @(posedge clk) begin
    if (!rst_n) begin
      msg_count     <= 32'd0;
      byte_count    <= 32'd0;
      gap_count     <= 32'd0;
      drop_count    <= 32'd0;
      cycle_count   <= 32'd0;
      occupancy_max <= 8'd0;
      since         <= 32'd0;
      hist0 <= 32'd0; hist1 <= 32'd0; hist2 <= 32'd0; hist3 <= 32'd0;
      hist4 <= 32'd0; hist5 <= 32'd0; hist6 <= 32'd0; hist7 <= 32'd0;
    end else begin
      cycle_count <= cycle_count + 32'd1;

      if (msg_valid) begin
        msg_count  <= msg_count + 32'd1;
        byte_count <= byte_count + {24'd0, msg_len};
        since      <= 32'd0;
        case (bin)
          3'd0: hist0 <= hist0 + 32'd1;
          3'd1: hist1 <= hist1 + 32'd1;
          3'd2: hist2 <= hist2 + 32'd1;
          3'd3: hist3 <= hist3 + 32'd1;
          3'd4: hist4 <= hist4 + 32'd1;
          3'd5: hist5 <= hist5 + 32'd1;
          3'd6: hist6 <= hist6 + 32'd1;
          default: hist7 <= hist7 + 32'd1;
        endcase
      end else begin
        since <= since + 32'd1;
      end

      if (gap_pulse)  gap_count  <= gap_count + 32'd1;
      if (drop_pulse) drop_count <= drop_count + 32'd1;
      if (occupancy > occupancy_max) occupancy_max <= occupancy;
    end
  end

endmodule

`endif
