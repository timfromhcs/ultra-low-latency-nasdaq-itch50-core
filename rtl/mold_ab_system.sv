// ============================================================================
// File: rtl/mold_ab_system.sv
// Module: mold_ab_system
// Description: Two redundant MoldUDP64 Ethernet feeds -> frame arbiter -> one
//              ITCH byte stream. Both pipelines share the network configuration;
//              the arbiter selects frames by Mold sequence (A on ties) and
//              signals gaps.
// ============================================================================
`ifndef MOLD_AB_SYSTEM_SV
`define MOLD_AB_SYSTEM_SV

`include "itch_pkg.sv"
`include "moldudp64_pipeline.sv"
`include "mold_feed_arbiter.sv"

module mold_ab_system #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8
)(
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire [31:0]                 cfg_dst_ip,
  input  wire [31:0]                 cfg_ip_mask,
  input  wire [15:0]                 cfg_udp_port,
  input  wire                        cfg_check_ip,
  input  wire                        cfg_check_port,
  input  wire [63:0]                 cfg_initial_seq,
  input  wire                        cfg_recovery_en,

  // Feed A (Ethernet frames)
  input  wire [DATA_WIDTH-1:0]       a_tdata,
  input  wire [BYTES_PER_WORD-1:0]   a_tkeep,
  input  wire                        a_tvalid,
  input  wire                        a_tlast,
  output wire                        a_tready,

  // Feed B (Ethernet frames)
  input  wire [DATA_WIDTH-1:0]       b_tdata,
  input  wire [BYTES_PER_WORD-1:0]   b_tkeep,
  input  wire                        b_tvalid,
  input  wire                        b_tlast,
  output wire                        b_tready,

  // Selected ITCH payload stream
  output wire [DATA_WIDTH-1:0]       m_tdata,
  output wire [BYTES_PER_WORD-1:0]   m_tkeep,
  output wire                        m_tvalid,
  output wire                        m_tlast,
  input  wire                        m_tready,

  // Observability
  output wire                        gap,
  output wire [31:0]                 gaps,
  output wire [31:0]                 dropped_a,
  output wire [31:0]                 dropped_b,
  output wire [31:0]                 frames_a,
  output wire [31:0]                 frames_b,
  output wire [63:0]                 expected_seq,
  output wire                        req_valid,
  output wire [63:0]                 req_seq,
  output wire [15:0]                 req_count,
  output wire                        abandon,
  output wire [31:0]                 requests,
  output wire [31:0]                 abandoned
);

  // --- Feed A pipeline ---
  wire [DATA_WIDTH-1:0]     a_p_tdata;
  wire [BYTES_PER_WORD-1:0] a_p_tkeep;
  wire                      a_p_tvalid;
  wire                      a_p_tlast;
  wire                      a_p_tready;
  wire [63:0]               a_p_seq;
  wire [15:0]               a_p_count;

  /* verilator lint_off PINCONNECTEMPTY */
  moldudp64_pipeline #(
    .DATA_WIDTH(DATA_WIDTH),
    .BYTES_PER_WORD(BYTES_PER_WORD)
  ) u_pipe_a (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_dst_ip(cfg_dst_ip),
    .cfg_ip_mask(cfg_ip_mask),
    .cfg_udp_port(cfg_udp_port),
    .cfg_check_ip(cfg_check_ip),
    .cfg_check_port(cfg_check_port),
    .cfg_initial_seq(cfg_initial_seq),
    .s_axis_tdata(a_tdata),
    .s_axis_tkeep(a_tkeep),
    .s_axis_tvalid(a_tvalid),
    .s_axis_tlast(a_tlast),
    .s_axis_tready(a_tready),
    .m_axis_tdata(a_p_tdata),
    .m_axis_tkeep(a_p_tkeep),
    .m_axis_tvalid(a_p_tvalid),
    .m_axis_tlast(a_p_tlast),
    .m_axis_tready(a_p_tready),
    .frame_ready(),
    .mold_session(),
    .mold_seq(),
    .mold_msg_count(),
    .mold_gap(),
    .mold_frame_ok(),
    .mold_frame_drop(),
    .frame_count(),
    .gap_count(),
    .drop_count(),
    .expected_seq(),
    .frame_seq(a_p_seq),
    .frame_msg_count(a_p_count)
  );

  // --- Feed B pipeline ---
  wire [DATA_WIDTH-1:0]     b_p_tdata;
  wire [BYTES_PER_WORD-1:0] b_p_tkeep;
  wire                      b_p_tvalid;
  wire                      b_p_tlast;
  wire                      b_p_tready;
  wire [63:0]               b_p_seq;
  wire [15:0]               b_p_count;

  moldudp64_pipeline #(
    .DATA_WIDTH(DATA_WIDTH),
    .BYTES_PER_WORD(BYTES_PER_WORD)
  ) u_pipe_b (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_dst_ip(cfg_dst_ip),
    .cfg_ip_mask(cfg_ip_mask),
    .cfg_udp_port(cfg_udp_port),
    .cfg_check_ip(cfg_check_ip),
    .cfg_check_port(cfg_check_port),
    .cfg_initial_seq(cfg_initial_seq),
    .s_axis_tdata(b_tdata),
    .s_axis_tkeep(b_tkeep),
    .s_axis_tvalid(b_tvalid),
    .s_axis_tlast(b_tlast),
    .s_axis_tready(b_tready),
    .m_axis_tdata(b_p_tdata),
    .m_axis_tkeep(b_p_tkeep),
    .m_axis_tvalid(b_p_tvalid),
    .m_axis_tlast(b_p_tlast),
    .m_axis_tready(b_p_tready),
    .frame_ready(),
    .mold_session(),
    .mold_seq(),
    .mold_msg_count(),
    .mold_gap(),
    .mold_frame_ok(),
    .mold_frame_drop(),
    .frame_count(),
    .gap_count(),
    .drop_count(),
    .expected_seq(),
    .frame_seq(b_p_seq),
    .frame_msg_count(b_p_count)
  );

  // --- Frame arbiter ---
  mold_feed_arbiter #(
    .DATA_WIDTH(DATA_WIDTH),
    .BYTES_PER_WORD(BYTES_PER_WORD)
  ) u_arb (
    .clk(clk),
    .rst_n(rst_n),
    .initial_seq(cfg_initial_seq),
    .recovery_en(cfg_recovery_en),
    .a_tdata(a_p_tdata),
    .a_tkeep(a_p_tkeep),
    .a_tvalid(a_p_tvalid),
    .a_tlast(a_p_tlast),
    .a_seq(a_p_seq),
    .a_count(a_p_count),
    .a_tready(a_p_tready),
    .b_tdata(b_p_tdata),
    .b_tkeep(b_p_tkeep),
    .b_tvalid(b_p_tvalid),
    .b_tlast(b_p_tlast),
    .b_seq(b_p_seq),
    .b_count(b_p_count),
    .b_tready(b_p_tready),
    .m_tdata(m_tdata),
    .m_tkeep(m_tkeep),
    .m_tvalid(m_tvalid),
    .m_tlast(m_tlast),
    .m_tready(m_tready),
    .gap(gap),
    .frames_a(frames_a),
    .frames_b(frames_b),
    .dropped_a(dropped_a),
    .dropped_b(dropped_b),
    .gaps(gaps),
    .overflows(),
    .expected_seq(expected_seq),
    .req_valid(req_valid),
    .req_seq(req_seq),
    .req_count(req_count),
    .abandon(abandon),
    .requests(requests),
    .abandoned(abandoned)
  );
  /* verilator lint_on PINCONNECTEMPTY */

endmodule

`endif
