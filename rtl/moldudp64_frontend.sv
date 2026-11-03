// ============================================================================
// File: rtl/moldudp64_frontend.sv
// Module: moldudp64_frontend
// Description: AXI4-Stream L2/L3/L4 + MoldUDP64 framing front-end.
//
//   Accepts complete Ethernet frames (tlast = end of frame), validates:
//     Ethernet II (optional single 802.1Q VLAN)
//     IPv4, IHL=5 (no IP options), protocol UDP
//     configurable destination IP + mask
//     configurable UDP destination port
//     MoldUDP64 header (10-byte session, 8-byte sequence, 2-byte count)
//   and emits only the ITCH payload bytes as a repacked AXI4-Stream.
//
//   Also exports session/sequence/count and a one-cycle `gap` pulse when the
//   MoldUDP64 sequence jumps. This is the feature the original core lacked.
//
//   Implementation notes:
//     * The first 96 bytes are captured (store-and-forward) so variable header
//       lengths are handled without a byte-at-a-time parser. This costs a few
//       cycles per frame (~5 cycles for 128-bit at 322 MHz) and is explicitly
//       reported in the latency budget.
//     * IPv4 options (IHL != 5), IPv6, jumbo frames > 96-byte headers are
//       dropped and counted. Documented limitation, not silent corruption.
//     * Downstream is assumed always-ready (same contract as itch_top).
// ============================================================================
`ifndef MOLDUDp64_FRONTEND_SV
`define MOLDUDp64_FRONTEND_SV

`include "itch_pkg.sv"

module moldudp64_frontend #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8,
  parameter HDR_BYTES = 96
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // Configuration
  input  wire [31:0]                 cfg_dst_ip,
  input  wire [31:0]                 cfg_ip_mask,
  input  wire [15:0]                 cfg_udp_port,
  input  wire                        cfg_check_ip,
  input  wire                        cfg_check_port,
  input  wire [63:0]                 cfg_initial_seq,
  input  wire                        frame_busy,

  // Ethernet frame ingress
  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [BYTES_PER_WORD-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  input  wire                        s_axis_tlast,
  output wire                        s_axis_tready,

  // ITCH payload egress (repacked, tlast on frame end)
  output reg  [DATA_WIDTH-1:0]       m_axis_tdata,
  output reg  [BYTES_PER_WORD-1:0]   m_axis_tkeep,
  output reg                         m_axis_tvalid,
  output reg                         m_axis_tlast,
  output reg                         m_axis_frame_end,
  output wire                        frame_ready,
  input  wire                        m_axis_tready,

  // Mold metadata / observability
  output reg  [79:0]                 mold_session,
  output reg  [63:0]                 mold_seq,
  output reg  [15:0]                 mold_msg_count,
  output reg                         mold_gap,
  output reg                         mold_frame_ok,
  output reg                         mold_frame_drop,
  output reg  [31:0]                 frame_count,
  output reg  [31:0]                 gap_count,
  output reg  [31:0]                 drop_count,
  output reg  [63:0]                 expected_seq
);

  localparam [2:0] ST_IDLE    = 3'd0;
  localparam [2:0] ST_CAPTURE = 3'd1;
  localparam [2:0] ST_DRAIN   = 3'd2;
  localparam [2:0] ST_STREAM  = 3'd3;
  localparam [2:0] ST_FLUSH   = 3'd4;
  localparam [2:0] ST_DISCARD = 3'd5;

  reg [2:0]  state;
  reg [HDR_BYTES*8-1:0] hdr_data;
  reg [7:0]  hdr_count;
  reg [7:0]  drain_ptr;
  reg        frame_tlast_q;
  reg        seq_valid;

  // Repacking output buffer
  reg [2*DATA_WIDTH-1:0] out_buf;
  reg [7:0]              out_count;

  // --------------------------------------------------------------------------
  // Helpers
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

  function automatic [7:0] hbyte(input [HDR_BYTES*8-1:0] d, input integer off);
    begin
      hbyte = (off < HDR_BYTES) ? d[off*8 +: 8] : 8'h00;
    end
  endfunction

  function automatic [15:0] be16(input [HDR_BYTES*8-1:0] d, input integer off);
    begin
      be16 = {hbyte(d, off), hbyte(d, off+1)};
    end
  endfunction

  function automatic [31:0] be32(input [HDR_BYTES*8-1:0] d, input integer off);
    begin
      be32 = {hbyte(d, off), hbyte(d, off+1), hbyte(d, off+2), hbyte(d, off+3)};
    end
  endfunction

  function automatic [63:0] be64(input [HDR_BYTES*8-1:0] d, input integer off);
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1)
        be64[63-i*8 -: 8] = hbyte(d, off+i);
    end
  endfunction

  function automatic [79:0] be80(input [HDR_BYTES*8-1:0] d, input integer off);
    integer i;
    begin
      for (i = 0; i < 10; i = i + 1)
        be80[79-i*8 -: 8] = hbyte(d, off+i);
    end
  endfunction

  // --------------------------------------------------------------------------
  // Ingress beat handling
  // --------------------------------------------------------------------------
  wire [7:0] in_bytes = (s_axis_tvalid && s_axis_tready) ? keep_to_bytes(s_axis_tkeep) : 8'd0;
  wire       in_accept = s_axis_tvalid && s_axis_tready;
  wire [DATA_WIDTH-1:0] in_masked = s_axis_tdata & keep_to_mask(s_axis_tkeep);

  // Capture next state
  wire [HDR_BYTES*8-1:0] hdr_data_next  = hdr_data | ({{(HDR_BYTES*8-DATA_WIDTH){1'b0}}, in_masked} << (hdr_count*8));
  wire [7:0]             hdr_count_next = hdr_count + in_bytes;

  // In IDLE a new frame starts from scratch (never from a stale capture).
  wire [HDR_BYTES*8-1:0] first_data  = {{(HDR_BYTES*8-DATA_WIDTH){1'b0}}, in_masked};
  wire [7:0]             first_count = in_bytes;
  wire [HDR_BYTES*8-1:0] cap_data    = (state == ST_IDLE) ? first_data : hdr_data_next;
  wire [7:0]             cap_count   = (state == ST_IDLE) ? first_count : hdr_count_next;

  // Fixed-offset header interpretation (IHL=5).
  wire        vlan        = (be16(cap_data, 12) == 16'h8100);
  wire        eth_ok      = (vlan ? be16(cap_data, 16) : be16(cap_data, 12)) == 16'h0800;
  wire [7:0]  ip_off      = vlan ? 8'd18 : 8'd14;
  wire [7:0]  ip_ver_ihl  = hbyte(cap_data, 32'(ip_off));
  wire [7:0]  ip_proto    = hbyte(cap_data, 32'(ip_off) + 9);
  wire [31:0] ip_dst      = be32(cap_data, 32'(ip_off) + 16);
  wire [15:0] udp_port    = be16(cap_data, 32'(ip_off) + 20 + 2);
  wire [7:0]  mold_off    = ip_off + 8'd28;
  wire [7:0]  payload_off = mold_off + 8'd20;
  wire        ip_ok       = (ip_ver_ihl[7:4] == 4'h4) && (ip_ver_ihl[3:0] == 4'h5);
  wire        ip_match    = !cfg_check_ip || ((ip_dst & cfg_ip_mask) == (cfg_dst_ip & cfg_ip_mask));
  wire        port_match  = !cfg_check_port || (udp_port == cfg_udp_port);
  wire        len_ok      = (cap_count >= payload_off);
  wire        frame_ok_now = eth_ok && ip_ok && (ip_proto == 8'h11) && ip_match && port_match && len_ok;

  wire [79:0] session_now = be80(cap_data, 32'(mold_off));
  wire [63:0] seq_now     = be64(cap_data, 32'(mold_off) + 10);
  wire [15:0] count_now   = be16(cap_data, 32'(mold_off) + 18);

  wire        decide = (cap_count >= 8'd72) || s_axis_tlast;

  // Only block the *start* of a new frame while the depacketizer still owns
  // the previous payload. The current frame's remaining beats must flow.
  wire out_ready = m_axis_tready || !m_axis_tvalid;

  assign frame_ready = (state == ST_IDLE) && !frame_busy;
  assign s_axis_tready = (state == ST_IDLE) ? !frame_busy :
                         (state == ST_CAPTURE && ({24'd0, hdr_count} <= (HDR_BYTES - BYTES_PER_WORD))) ||
                         (state == ST_STREAM && out_ready) || (state == ST_DISCARD);

  // --------------------------------------------------------------------------
  // Drain feed (from captured header)
  // --------------------------------------------------------------------------
  wire [7:0] drain_avail = (hdr_count > drain_ptr) ? (hdr_count - drain_ptr) : 8'd0;
  wire [7:0] drain_n     = (drain_avail >= 8'(BYTES_PER_WORD)) ? BYTES_PER_WORD[7:0] : drain_avail;
  /* verilator lint_off WIDTHTRUNC */
  wire [DATA_WIDTH-1:0] drain_data = hdr_data >> (drain_ptr*8);
  /* verilator lint_on WIDTHTRUNC */

  // --------------------------------------------------------------------------
  // Output repacker
  // --------------------------------------------------------------------------
  wire [7:0]           feed_bytes = (state == ST_DRAIN) ? drain_n : in_bytes;
  wire                 feed_space_ok = ({24'd0, feed_bytes} <= (2*BYTES_PER_WORD - {24'd0, rem_count}));
  wire                 feed_valid = ((state == ST_DRAIN && out_ready) ||
                                    (state == ST_STREAM && in_accept)) && feed_space_ok;
  wire [DATA_WIDTH-1:0] feed_data = (state == ST_DRAIN) ? drain_data : in_masked;

  wire                 emit_full = (out_count >= 8'(BYTES_PER_WORD));
  wire                 emit_any  = emit_full || (state == ST_FLUSH && out_count > 8'd0);
  wire [7:0]           emit_n    = emit_full ? BYTES_PER_WORD[7:0] : out_count;
  wire                 do_emit   = emit_any && out_ready;
  // When nothing is emitted, keep every buffered byte. Using emit_n here
  // would shift the buffer by out_count and silently drop the tail.
  wire [7:0]           emit_eff  = do_emit ? emit_n : 8'd0;
  wire [2*DATA_WIDTH-1:0] shifted = out_buf >> (emit_eff*8);
  wire [7:0]           rem_count = out_count - emit_eff;
  wire [2*DATA_WIDTH-1:0] appended = feed_valid ?
        ({{(2*DATA_WIDTH-DATA_WIDTH){1'b0}}, feed_data} << (rem_count*8)) : {2*DATA_WIDTH{1'b0}};
  wire [7:0]           next_out_count = rem_count + (feed_valid ? feed_bytes : 8'd0);
  // The frame's last byte is emitted in this cycle: either the input tlast was
  // accepted now, or it was accepted earlier and this emit empties the buffer.
  // Without this a frame whose payload ends on a full beat never asserts tlast.
  wire                 input_done_now = frame_tlast_q || (in_accept && s_axis_tlast);
  wire                 final_emit     = do_emit && (next_out_count == 8'd0) && input_done_now;
  wire [DATA_WIDTH-1:0] emit_mask = ({24'd0, emit_n} >= BYTES_PER_WORD) ? {DATA_WIDTH{1'b1}} :
        (({{(DATA_WIDTH-1){1'b0}}, 1'b1} << (emit_n*8)) - 1'b1);

  always @(posedge clk) begin
    if (!rst_n) begin
      state           <= ST_IDLE;
      hdr_data        <= {HDR_BYTES*8{1'b0}};
      hdr_count       <= 8'd0;
      drain_ptr       <= 8'd0;
      frame_tlast_q   <= 1'b0;
      seq_valid       <= 1'b0;
      expected_seq  <= cfg_initial_seq;
      out_buf         <= {2*DATA_WIDTH{1'b0}};
      out_count       <= 8'd0;
      m_axis_tdata    <= {DATA_WIDTH{1'b0}};
      m_axis_tkeep    <= {BYTES_PER_WORD{1'b0}};
      m_axis_tvalid   <= 1'b0;
      m_axis_tlast    <= 1'b0;
      m_axis_frame_end<= 1'b0;
      mold_session    <= 80'd0;
      mold_seq        <= 64'd0;
      mold_msg_count  <= 16'd0;
      mold_gap        <= 1'b0;
      mold_frame_ok   <= 1'b0;
      mold_frame_drop <= 1'b0;
      frame_count     <= 32'd0;
      gap_count       <= 32'd0;
      drop_count      <= 32'd0;
      expected_seq    <= cfg_initial_seq;
    end else begin
      // Defaults
      m_axis_frame_end<= 1'b0;
      mold_gap        <= 1'b0;
      mold_frame_ok   <= 1'b0;
      mold_frame_drop <= 1'b0;

      // Emit one repacked beat; hold it (with tlast) until accepted.
      if (m_axis_tvalid && m_axis_tready) begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
      end

      if (do_emit) begin
        m_axis_tvalid <= 1'b1;
        m_axis_tdata  <= out_buf[DATA_WIDTH-1:0] & emit_mask;
        m_axis_tkeep  <= ({24'd0, emit_n} >= BYTES_PER_WORD) ? {BYTES_PER_WORD{1'b1}} :
                         (({{(BYTES_PER_WORD-1){1'b0}}, 1'b1} << emit_n) - 1'b1);
        m_axis_tlast  <= final_emit;
      end

      // frame_end is a handshake event: the last beat must be accepted.
      if (m_axis_tvalid && m_axis_tready && m_axis_tlast)
        m_axis_frame_end <= 1'b1;

      if (do_emit || feed_valid) begin
        out_buf   <= shifted | appended;
        out_count <= next_out_count;
      end

      case (state)
        ST_IDLE, ST_CAPTURE: begin
          if (in_accept) begin
            hdr_data      <= cap_data;
            hdr_count     <= cap_count;
            frame_tlast_q <= s_axis_tlast;

            if (decide) begin
              frame_count <= frame_count + 32'd1;
              if (frame_ok_now) begin
                mold_frame_ok  <= 1'b1;
                mold_session   <= session_now;
                mold_seq       <= seq_now;
                mold_msg_count <= count_now;
                if (seq_valid && (seq_now != expected_seq)) begin
                  mold_gap  <= 1'b1;
                  gap_count <= gap_count + 32'd1;
                end
                seq_valid    <= 1'b1;
                expected_seq <= seq_now + {48'd0, count_now};
                drain_ptr    <= payload_off;
                if (cap_count > payload_off) state <= ST_DRAIN;
                else if (s_axis_tlast)       state <= ST_FLUSH;
                else                         state <= ST_STREAM;
              end else begin
                mold_frame_drop <= 1'b1;
                drop_count      <= drop_count + 32'd1;
                hdr_data        <= {HDR_BYTES*8{1'b0}};
                hdr_count       <= 8'd0;
                drain_ptr       <= 8'd0;
                state           <= s_axis_tlast ? ST_FLUSH : ST_DISCARD;
              end
            end else begin
              state <= ST_CAPTURE;
            end
          end
        end

        ST_DRAIN: begin
          if (feed_valid) begin
            if (drain_avail > 8'd0)
              drain_ptr <= drain_ptr + drain_n;
            if (drain_ptr + drain_n >= hdr_count)
              state <= frame_tlast_q ? ST_FLUSH : ST_STREAM;
          end
        end

        ST_STREAM: begin
          if (in_accept && s_axis_tlast) begin
            frame_tlast_q <= 1'b1;
            state <= ST_FLUSH;
          end
        end

        ST_DISCARD: begin
          if (in_accept && s_axis_tlast) begin
            hdr_count <= 8'd0;
            hdr_data  <= {HDR_BYTES*8{1'b0}};
            drain_ptr <= 8'd0;
            state     <= ST_FLUSH;
          end
        end

        ST_FLUSH: begin
          if (out_count == 8'd0 || (do_emit && rem_count == 8'd0)) begin
            state           <= ST_IDLE;
            hdr_count       <= 8'd0;
            hdr_data        <= {HDR_BYTES*8{1'b0}};
            drain_ptr       <= 8'd0;
            // Frame boundary for the downstream stage. For frames with no
            // payload beat there is nothing to handshake; otherwise the
            // handshake pulse below covers it.
            if (!m_axis_tvalid) m_axis_frame_end <= 1'b1;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Simulation checks
  // --------------------------------------------------------------------------
  // synthesis translate_off
  always @(posedge clk) begin
    if (rst_n) begin
      if ({24'd0, next_out_count} > 2*BYTES_PER_WORD)
        $error("moldudp64_frontend: out_count overflow %0d", next_out_count);
      if (hdr_count > HDR_BYTES)
        $error("moldudp64_frontend: header capture overflow");
    end
  end
  // synthesis translate_on

endmodule

`endif
