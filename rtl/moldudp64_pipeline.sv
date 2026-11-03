// ============================================================================
// File: rtl/moldudp64_pipeline.sv
// Module: moldudp64_pipeline
// Description: Ethernet/IPv4/UDP/MoldUDP64 front-end + per-message length
//              stripper. Output is a pure ITCH 5.0 byte stream.
// ============================================================================
`ifndef MOLDUDp64_PIPELINE_SV
`define MOLDUDp64_PIPELINE_SV

`include "itch_pkg.sv"
`include "moldudp64_frontend.sv"
`include "moldudp64_depacketizer.sv"

module moldudp64_pipeline #(
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

  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [BYTES_PER_WORD-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  output wire [DATA_WIDTH-1:0]       m_axis_tdata,
  output wire [BYTES_PER_WORD-1:0]   m_axis_tkeep,
  output wire                        m_axis_tvalid,
  output wire                        m_axis_tlast,
  output wire                        frame_ready,

  output wire [79:0]                 mold_session,
  output wire [63:0]                 mold_seq,
  output wire [15:0]                 mold_msg_count,
  output wire [63:0]                 frame_seq,
  output wire [15:0]                 frame_msg_count,
  output wire                        mold_gap,
  output wire                        mold_frame_ok,
  output wire                        mold_frame_drop,
  output wire [31:0]                 frame_count,
  output wire [31:0]                 gap_count,
  output wire [31:0]                 drop_count,
  output wire [63:0]                 expected_seq
);

  wire [DATA_WIDTH-1:0]     fe_tdata;
  wire [BYTES_PER_WORD-1:0] fe_tkeep;
  wire                      fe_tvalid;
  wire                      fe_tlast;
  wire                      fe_m_axis_tready;
  wire                      fe_frame_end;
  wire                      dep_busy;
  wire                      frame_busy = dep_busy;

  // Align the depacketizer with accepted payload beats, not with a beat that is
  // merely being presented. A held beat (tready low) must not re-trigger a frame
  // start, and frame_end must pulse only when the last beat actually handshakes.
  reg fe_in_frame;
  wire fe_accept = fe_tvalid && fe_m_axis_tready;
  wire fe_frame_start = fe_accept && !fe_in_frame;
  always @(posedge clk) begin
    if (!rst_n) fe_in_frame <= 1'b0;
    else if (fe_frame_end) fe_in_frame <= 1'b0;
    else if (fe_accept && fe_tlast) fe_in_frame <= 1'b0;
    else if (fe_accept) fe_in_frame <= 1'b1;
  end

  moldudp64_frontend #(
    .DATA_WIDTH(DATA_WIDTH),
    .BYTES_PER_WORD(BYTES_PER_WORD)
  ) u_frontend (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_dst_ip(cfg_dst_ip),
    .cfg_ip_mask(cfg_ip_mask),
    .cfg_udp_port(cfg_udp_port),
    .cfg_check_ip(cfg_check_ip),
    .cfg_check_port(cfg_check_port),
    .cfg_initial_seq(cfg_initial_seq),
    .frame_busy(frame_busy),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(fe_tdata),
    .m_axis_tkeep(fe_tkeep),
    .m_axis_tvalid(fe_tvalid),
    .m_axis_tlast(fe_tlast),
    .m_axis_frame_end(fe_frame_end),
    .frame_ready(frame_ready),
    .m_axis_tready(fe_m_axis_tready),
    .mold_session(mold_session),
    .mold_seq(mold_seq),
    .mold_msg_count(mold_msg_count),
    .mold_gap(mold_gap),
    .mold_frame_ok(mold_frame_ok),
    .mold_frame_drop(mold_frame_drop),
    .frame_count(frame_count),
    .gap_count(gap_count),
    .drop_count(drop_count),
    .expected_seq(expected_seq)
  );

  /* verilator lint_off PINCONNECTEMPTY */
  moldudp64_depacketizer #(
    .DATA_WIDTH(DATA_WIDTH),
    .BYTES_PER_WORD(BYTES_PER_WORD)
  ) u_depacketizer (
    .clk(clk),
    .rst_n(rst_n),
    .msg_count(mold_msg_count),
    .frame_start(fe_frame_start),
    .frame_end(fe_frame_end),
    .s_axis_tdata(fe_tdata),
    .s_axis_tkeep(fe_tkeep),
    .s_axis_tvalid(fe_tvalid),
    .s_axis_tready(fe_m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(m_axis_tlast),
    .msgs_left(),
    .frame_done(),
    .busy(dep_busy)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Frame sidebands: valid while the frame's payload is on the output stream.
  assign frame_seq       = mold_seq;
  assign frame_msg_count = mold_msg_count;

endmodule

`endif
