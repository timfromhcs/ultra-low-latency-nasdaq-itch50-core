// ============================================================================
// File: rtl/itch_wishbone_wrap.sv
// Module: itch_wishbone_wrap
// Description: Caravel-friendly wrapper: the parser's host register port is
//              exposed through a classic Wishbone slave (Caravel's management
//              bus), while the ITCH byte stream still enters on AXI4-Stream.
//
//   Wishbone: 32-bit data, 5-bit address, read-only register file. Reads ACK one
//   cycle after cyc&stb; writes are acknowledged but ignored (no write port).
//   Register map is itch_host_wrap's (0 msg_count, 1 corrupt, 2 type|locate,
//   3 price, 4/5 shares, 6/7 ref, 8 flags, 9 bytes, 10 updates).
// ============================================================================
`timescale 1ns/1ps

`ifndef ITCH_WISHBONE_WRAP_SV
`define ITCH_WISHBONE_WRAP_SV

module itch_wishbone_wrap #(
  parameter DATA_WIDTH = 128
)(
  input  wire         clk,
  input  wire         rst_n,

  input  wire [DATA_WIDTH-1:0]     s_axis_tdata,
  input  wire [(DATA_WIDTH/8)-1:0] s_axis_tkeep,
  input  wire         s_axis_tvalid,
  input  wire         s_axis_tlast,
  output wire         s_axis_tready,

  // Wishbone slave (classic)
  input  wire         wb_cyc,
  input  wire         wb_stb,
  input  wire         wb_we,
  input  wire [4:0]   wb_adr,
  input  wire [31:0]  wb_dat_w,
  input  wire [3:0]   wb_sel,
  output reg          wb_ack,
  output reg  [31:0]  wb_dat_r
);

  wire [31:0] host_rdata;

  // The register file is read-only; the write data/select are accepted but unused.
  wire _unused = &{1'b0, wb_dat_w, wb_sel};

  itch_host_wrap #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_host (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .host_addr(wb_adr),
    .host_rdata(host_rdata)
  );

  // One-cycle ACK. The register file is combinational, so the read data is valid
  // on the same edge that raises ACK.
  always @(posedge clk) begin
    if (!rst_n) begin
      wb_ack <= 1'b0;
      wb_dat_r <= 32'd0;
    end else begin
      wb_ack <= wb_cyc && wb_stb;
      if (wb_cyc && wb_stb && !wb_we) begin
        wb_dat_r <= host_rdata;
      end
    end
  end

endmodule

`endif
