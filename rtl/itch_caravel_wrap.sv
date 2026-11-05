// ============================================================================
// File: rtl/itch_caravel_wrap.sv
// Module: itch_caravel_wrap
// Description: Caravel-style user project wrapper. Maps the 32-bit Wishbone
//              management bus to the host register file and carries the ITCH
//              byte stream on the 38-bit io_in bus:
//
//   io_in[31:0]  s_axis_tdata
//   io_in[35:32] s_axis_tkeep
//   io_in[36]    s_axis_tvalid
//   io_in[37]    s_axis_tlast
//   io_out[0]    s_axis_tready   (io_oeb[0] = 0, all other oeb = 1)
//
//   Wishbone byte address -> word address: wb_adr_i[6:2].
//
//   This is the Caravel-shaped boundary, not a verified Caravel harness run.
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_CARAVEL_WRAP_SV
`define ITCH_CARAVEL_WRAP_SV

module itch_caravel_wrap (
  input  wire         wb_clk_i,
  input  wire         wb_rst_i,

  input  wire         wbs_stb_i,
  input  wire         wbs_cyc_i,
  input  wire         wbs_we_i,
  input  wire [3:0]   wbs_sel_i,
  input  wire [31:0]  wbs_dat_i,
  input  wire [31:0]  wbs_adr_i,
  output wire         wbs_ack_o,
  output wire [31:0]  wbs_dat_o,

  input  wire [37:0]  io_in,
  output wire [37:0]  io_out,
  output wire [37:0]  io_oeb,

  input  wire [127:0] la_data_in,
  output wire [127:0] la_data_out,
  input  wire [127:0] la_oenb,

  output wire [2:0]   user_irq
);

  wire tready;

  itch_wishbone_wrap #(
    .DATA_WIDTH(32)
  ) u_itch (
    .clk(wb_clk_i),
    .rst_n(~wb_rst_i),
    .s_axis_tdata(io_in[31:0]),
    .s_axis_tkeep(io_in[35:32]),
    .s_axis_tvalid(io_in[36]),
    .s_axis_tlast(io_in[37]),
    .s_axis_tready(tready),
    .wb_cyc(wbs_cyc_i),
    .wb_stb(wbs_stb_i),
    .wb_we(wbs_we_i),
    .wb_adr(wbs_adr_i[6:2]),
    .wb_dat_w(wbs_dat_i),
    .wb_sel(wbs_sel_i),
    .wb_ack(wbs_ack_o),
    .wb_dat_r(wbs_dat_o)
  );

  assign io_out = {37'd0, tready};
  assign io_oeb = 38'h3F_FFFF_FFFE;   // only io_out[0] driven

  assign la_data_out = 128'd0;
  assign user_irq = 3'd0;

  // Only the word-aligned address bits and the la_* inputs are unused here.
  wire _unused = &{1'b0, wbs_adr_i[31:7], wbs_adr_i[1:0], la_data_in, la_oenb};

endmodule

`endif
