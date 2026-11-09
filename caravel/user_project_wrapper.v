// ============================================================================
// File: caravel/user_project_wrapper.v
// Module: user_project_wrapper
// Description: Drop-in Caravel user-project wrapper. Caravel instantiates this
//              exact module name/port list; it forwards to ChipLab's ITCH core
//              (32-bit AXI stream on io_in, Wishbone register file, no IRQ).
//
//   Copy this file and the rtl/ sources into a Caravel user project's
//   verilog/rtl/ directory and point the project's wrapper at it.
// ============================================================================
`timescale 1ns/1ps

module user_project_wrapper (
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

  input  wire [127:0] la_data_in,
  output wire [127:0] la_data_out,
  input  wire [127:0] la_oenb,

  input  wire [37:0]  io_in,
  output wire [37:0]  io_out,
  output wire [37:0]  io_oeb,

  output wire [2:0]   user_irq
);

  itch_caravel_wrap u_itch (
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(wbs_stb_i),
    .wbs_cyc_i(wbs_cyc_i),
    .wbs_we_i(wbs_we_i),
    .wbs_sel_i(wbs_sel_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_ack_o(wbs_ack_o),
    .wbs_dat_o(wbs_dat_o),
    .io_in(io_in),
    .io_out(io_out),
    .io_oeb(io_oeb),
    .la_data_in(la_data_in),
    .la_data_out(la_data_out),
    .la_oenb(la_oenb),
    .user_irq(user_irq)
  );

endmodule
