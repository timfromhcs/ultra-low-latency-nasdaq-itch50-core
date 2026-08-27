// ============================================================================
// File: rtl/itch_shifter.sv
// Module: itch_shifter
// Description: Sub-Word Lookahead Shifter & Barrel Matrix.
//              Resolves message offsets crossing 64/128-bit word boundaries
//              with 0 latency penalty (single-cycle barrel sliding window).
// Target: ASIC / High-Frequency Trading FPGA (25GbE / 100GbE Line Rate)
// ============================================================================
`ifndef ITCH_SHIFTER_SV
`define ITCH_SHIFTER_SV

`include "itch_pkg.sv"

module itch_shifter #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8,
  parameter BUFFER_BYTES = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // AXI4-Stream Input Interface
  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire                        s_axis_tvalid,
  /* verilator lint_off UNUSED */
  input  wire                        s_axis_tlast,
  /* verilator lint_on UNUSED */
  output wire                        s_axis_tready,

  // Consumer Feedback Interface
  input  wire                        consume_valid,
  input  wire [7:0]                  consume_bytes,

  // Sliding Lookahead Window Output to Parser Core
  output wire [511:0]                window_data,
  output wire [7:0]                  window_valid_bytes,
  output wire                        window_has_msg,
  output wire [7:0]                  buffer_occupancy
);

  // Storage Buffer implemented as packed vector for ultra-fast barrel shifting
  reg [(BUFFER_BYTES*8)-1:0] buf_data;
  reg [7:0]                  buf_count; // Valid bytes currently in buffer

  // We are ready to accept data if buffer has space for at least 1 word
  assign s_axis_tready     = (buf_count <= (BUFFER_BYTES - BYTES_PER_WORD));
  assign buffer_occupancy  = buf_count;

  // Combinatorial Lookahead Window: directly slice 64 bytes (512 bits) from buf_data
  assign window_data        = buf_data[511:0];
  assign window_valid_bytes = (buf_count >= 8'd64) ? 8'd64 : buf_count;
  assign window_has_msg     = (buf_count > 8'd0);

  // Combinatorial Next-State Logic
  wire [7:0]                  eff_consume;
  wire [7:0]                  post_consume_count;
  wire [(BUFFER_BYTES*8)-1:0] shifted_data;
  wire [(BUFFER_BYTES*8)-1:0] next_data;
  wire [7:0]                  next_count;

  assign eff_consume        = (consume_valid && (consume_bytes <= buf_count)) ? consume_bytes : 8'd0;
  assign shifted_data       = buf_data >> (eff_consume * 8);
  assign post_consume_count = buf_count - eff_consume;

  assign next_data = (s_axis_tvalid && s_axis_tready) ?
                     (shifted_data | ({{((BUFFER_BYTES-BYTES_PER_WORD)*8){1'b0}}, s_axis_tdata} << (post_consume_count * 8))) :
                     shifted_data;

  assign next_count = (s_axis_tvalid && s_axis_tready) ?
                      (post_consume_count + 8'd16) :
                      post_consume_count;

  // Synchronous State Update
  always @(posedge clk) begin
    if (!rst_n) begin
      buf_count <= 8'd0;
      buf_data  <= {(BUFFER_BYTES*8){1'b0}};
    end else begin
      buf_count <= next_count;
      buf_data  <= next_data;
    end
  end

endmodule

`endif