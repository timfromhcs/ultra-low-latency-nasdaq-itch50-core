// ============================================================================
// File: rtl/itch_shifter.sv
// Module: itch_shifter
// Description: AXI4-Stream ingress de-framer + 512-bit sliding lookahead.
//
//   * tkeep-aware: partial beats are appended with their exact byte count.
//   * tlast-aware: frame boundaries are exported for accounting/resync.
//   * Cleared append window: bytes beyond the valid occupancy are masked to
//     zero before the new word is OR-ed in. This is required once tkeep can
//     produce short beats (the original design assumed every beat was 16 B).
//   * Generic DATA_WIDTH: 128 (41.25 Gbps @ 322.26 MHz), 256, 512.
//
//   Latency (defined reference point!):
//     s_axis_tdata -> buf_data register : 1 clock
//     buf_data      -> window_data      : combinational
//     parser        -> m_* register     : 1 clock
//     => true wire-to-registered-output is 2 clocks (6.20 ns @ 322.26 MHz).
//     The async bypass is 1 clock + the parser mux delay, NOT 0 clocks.
// ============================================================================
`ifndef ITCH_SHIFTER_SV
`define ITCH_SHIFTER_SV

`include "itch_pkg.sv"

module itch_shifter #(
  parameter DATA_WIDTH    = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8,
  parameter WINDOW_BYTES  = 64,
  parameter BUFFER_BYTES  = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // AXI4-Stream input
  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [BYTES_PER_WORD-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  // Consumer feedback (one message per cycle, 0..WINDOW_BYTES bytes)
  input  wire                        consume_valid,
  input  wire [7:0]                  consume_bytes,

  // Sliding lookahead window
  output wire [WINDOW_BYTES*8-1:0]   window_data,
  output wire [7:0]                  window_valid_bytes,
  output wire                        window_has_msg,
  output wire [7:0]                  buffer_occupancy,

  // Frame accounting
  output reg                         last_pulse,
  output reg  [31:0]                 beat_count,
  output reg  [31:0]                 frame_count
);

  // --------------------------------------------------------------------------
  // Byte/word helpers
  // --------------------------------------------------------------------------
  function automatic [7:0] keep_to_bytes(input [BYTES_PER_WORD-1:0] keep);
    integer i;
    begin
      keep_to_bytes = 8'd0;
      for (i = 0; i < BYTES_PER_WORD; i = i + 1)
        if (keep[i]) keep_to_bytes = keep_to_bytes + 8'd1;
    end
  endfunction

  function automatic [BYTES_PER_WORD*8-1:0] keep_to_mask(input [BYTES_PER_WORD-1:0] keep);
    integer i;
    begin
      for (i = 0; i < BYTES_PER_WORD; i = i + 1)
        keep_to_mask[i*8 +: 8] = {8{keep[i]}};
    end
  endfunction

  // --------------------------------------------------------------------------
  // Storage
  // --------------------------------------------------------------------------
  reg [BUFFER_BYTES*8-1:0] buf_data;
  reg [7:0]                buf_count;

  wire [7:0] word_bytes = (s_axis_tvalid && s_axis_tready) ? keep_to_bytes(s_axis_tkeep) : 8'd0;
  wire       accept     = s_axis_tvalid && s_axis_tready;

  // Ready whenever a full word can still fit. Short beats also fit.
  assign s_axis_tready    = ({24'd0, buf_count} <= (BUFFER_BYTES - BYTES_PER_WORD));
  assign buffer_occupancy = buf_count;

  // --------------------------------------------------------------------------
  // Lookahead window (combinational slice)
  // --------------------------------------------------------------------------
  assign window_data        = buf_data[WINDOW_BYTES*8-1:0];
  assign window_valid_bytes = (buf_count >= WINDOW_BYTES[7:0]) ? WINDOW_BYTES[7:0] : buf_count;
  assign window_has_msg     = (buf_count > 8'd0);

  // --------------------------------------------------------------------------
  // Next-state logic
  // --------------------------------------------------------------------------
  wire [7:0]                  eff_consume;
  wire [7:0]                  post_consume_count;
  wire [BUFFER_BYTES*8-1:0]   cleared_data;
  wire [BUFFER_BYTES*8-1:0]   shifted_data;
  wire [DATA_WIDTH-1:0]       keep_masked_data;
  wire [BUFFER_BYTES*8-1:0]   append_data;
  wire [BUFFER_BYTES*8-1:0]   next_data;
  wire [7:0]                  next_count;

  assign eff_consume = (consume_valid && (consume_bytes <= buf_count) && (consume_bytes > 8'd0))
                       ? consume_bytes : 8'd0;

  // Mask off everything at/above the valid occupancy before shifting. This is
  // the fix for the original design's stale-byte OR (latent with 16 B beats,
  // fatal with tkeep-short beats).
  assign cleared_data = buf_data & ~({{(BUFFER_BYTES*8-1){1'b0}}, 1'b1} << (buf_count * 8));
  assign shifted_data = cleared_data >> (eff_consume * 8);
  assign post_consume_count = buf_count - eff_consume;

  assign keep_masked_data = s_axis_tdata & keep_to_mask(s_axis_tkeep);
  assign append_data      = {{(BUFFER_BYTES*8-DATA_WIDTH){1'b0}}, keep_masked_data}
                            << (post_consume_count * 8);

  assign next_data  = shifted_data | (accept ? append_data : {BUFFER_BYTES*8{1'b0}});
  assign next_count = post_consume_count + (accept ? word_bytes : 8'd0);

  // --------------------------------------------------------------------------
  // Sequential state + accounting
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      buf_count   <= 8'd0;
      buf_data    <= {BUFFER_BYTES*8{1'b0}};
      last_pulse  <= 1'b0;
      beat_count  <= 32'd0;
      frame_count <= 32'd0;
    end else begin
      buf_count <= next_count;
      buf_data  <= next_data;

      last_pulse <= accept && s_axis_tlast;
      if (accept) begin
        beat_count <= beat_count + 32'd1;
        if (s_axis_tlast) frame_count <= frame_count + 32'd1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Simulation-only safety checks
  // --------------------------------------------------------------------------
  // synthesis translate_off
  always @(posedge clk) begin
    if (rst_n) begin
      if (next_count > BUFFER_BYTES)
        $error("itch_shifter: buffer overflow: next_count=%0d", next_count);
      if (eff_consume > buf_count)
        $error("itch_shifter: over-consume");
    end
  end
  // synthesis translate_on

endmodule

`endif
