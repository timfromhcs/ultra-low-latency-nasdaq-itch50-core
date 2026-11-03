// ============================================================================
// File: rtl/mold_feed_arbiter.sv
// Module: mold_feed_arbiter
// Description: A/B frame-level arbiter for redundant MoldUDP64 feeds.
//
//   Each feed presents complete ITCH payload frames on an AXI4-Stream, with the
//   Mold sequence number and message count as sidebands. The arbiter stores one
//   frame per feed (store-and-forward, <= 2 KB) and selects the frame whose
//   sequence number equals the expected value; on a tie it prefers A, and if
//   neither matches it takes the lower sequence and pulses `gap` (sequence
//   recovery is the caller's job). The loser is discarded.
//
//   If only one feed has a frame, the arbiter waits up to TIMEOUT cycles for
//   the other (redundancy window) and then forwards the available frame.
// ============================================================================
`ifndef MOLD_FEED_ARBITER_SV
`define MOLD_FEED_ARBITER_SV

`include "itch_pkg.sv"

module mold_feed_arbiter #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8,
  parameter MAX_WORDS = 128,          // 2 KB per feed
  parameter TIMEOUT = 64
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire [63:0]                 initial_seq,
  input  wire                        recovery_en,

  // Feed A
  input  wire [DATA_WIDTH-1:0]       a_tdata,
  input  wire [BYTES_PER_WORD-1:0]   a_tkeep,
  input  wire                        a_tvalid,
  input  wire                        a_tlast,
  input  wire [63:0]                 a_seq,
  input  wire [15:0]                 a_count,
  output wire                        a_tready,

  // Feed B
  input  wire [DATA_WIDTH-1:0]       b_tdata,
  input  wire [BYTES_PER_WORD-1:0]   b_tkeep,
  input  wire                        b_tvalid,
  input  wire                        b_tlast,
  input  wire [63:0]                 b_seq,
  input  wire [15:0]                 b_count,
  output wire                        b_tready,

  // Selected output stream
  output reg  [DATA_WIDTH-1:0]       m_tdata,
  output reg  [BYTES_PER_WORD-1:0]   m_tkeep,
  output reg                         m_tvalid,
  output reg                         m_tlast,
  input  wire                        m_tready,

  // Observability
  output reg                         gap,
  output reg  [31:0]                 frames_a,
  output reg  [31:0]                 frames_b,
  output reg  [31:0]                 dropped_a,
  output reg  [31:0]                 dropped_b,
  output reg  [31:0]                 gaps,
  output reg  [31:0]                 overflows,
  output reg  [63:0]                 expected_seq,
  output reg                         req_valid,
  output reg  [63:0]                 req_seq,
  output reg  [15:0]                 req_count,
  output reg                         abandon,
  output reg  [31:0]                 requests,
  output reg  [31:0]                 abandoned
);

  reg [DATA_WIDTH-1:0]     mem_a [0:MAX_WORDS-1];
  reg [BYTES_PER_WORD-1:0] kep_a [0:MAX_WORDS-1];
  reg [DATA_WIDTH-1:0]     mem_b [0:MAX_WORDS-1];
  reg [BYTES_PER_WORD-1:0] kep_b [0:MAX_WORDS-1];
  reg                      lst_a [0:MAX_WORDS-1];
  reg                      lst_b [0:MAX_WORDS-1];

  reg [7:0]  wa_a, wa_b;
  reg [7:0]  ra;
  reg        full_a, full_b;
  reg        in_a, in_b;
  reg        disc_a, disc_b;
  reg [63:0] sa, sb;
  reg [15:0] ca, cb;
  reg [15:0] wait_a, wait_b;

  localparam [1:0] ST_IDLE   = 2'd0;
  localparam [1:0] ST_STREAM = 2'd1;
  localparam [9:0] REC_TIMEOUT = 10'd256;

  reg [1:0] state;
  reg       win_a;
  reg       req_pending;
  reg [9:0] req_timer;
  reg       force_accept;

  assign a_tready = !full_a;
  assign b_tready = !full_b;

  wire a_first = a_tvalid && a_tready && !in_a && !disc_a;
  wire b_first = b_tvalid && b_tready && !in_b && !disc_b;
  wire a_take  = a_tvalid && a_tready;
  wire b_take  = b_tvalid && b_tready;

  wire both_full = full_a && full_b;
  wire only_a    = full_a && !full_b;
  wire only_b    = full_b && !full_a;
  wire match_a   = full_a && (sa == expected_seq);
  wire match_b   = full_b && (sb == expected_seq);

  reg  decide;
  reg  pick_a;
  always @(*) begin
    decide = 1'b0;
    pick_a = 1'b1;
    if (both_full) begin
      decide = 1'b1;
      if (match_a)       pick_a = 1'b1;
      else if (match_b)  pick_a = 1'b0;
      else               pick_a = (sa <= sb);
    end else if (only_a && (wait_a >= TIMEOUT)) begin
      decide = 1'b1; pick_a = 1'b1;
    end else if (only_b && (wait_b >= TIMEOUT)) begin
      decide = 1'b1; pick_a = 1'b0;
    end
  end

  wire [7:0] nra = (m_tvalid && m_tready && !m_tlast) ? ra + 8'd1 : ra;

  wire win_gap = pick_a ? (sa != expected_seq) : (sb != expected_seq);
  wire [63:0] miss = pick_a ? (sa - expected_seq) : (sb - expected_seq);
  wire [63:0] win_seq = pick_a ? sa : sb;
  wire [15:0] win_cnt = pick_a ? ca : cb;

  // Single clocked block: capture, wait counters, arbitration, output stream.
  always @(posedge clk) begin
    if (!rst_n) begin
      wa_a <= 8'd0; wa_b <= 8'd0;
      ra <= 8'd0;
      full_a <= 1'b0; full_b <= 1'b0;
      in_a <= 1'b0; in_b <= 1'b0;
      disc_a <= 1'b0; disc_b <= 1'b0;
      sa <= 64'd0; sb <= 64'd0; ca <= 16'd0; cb <= 16'd0;
      wait_a <= 16'd0; wait_b <= 16'd0;
      frames_a <= 32'd0; frames_b <= 32'd0;
      dropped_a <= 32'd0; dropped_b <= 32'd0;
      overflows <= 32'd0;
      state <= ST_IDLE;
      win_a <= 1'b1;
      m_tvalid <= 1'b0;
      m_tdata <= {DATA_WIDTH{1'b0}};
      m_tkeep <= {BYTES_PER_WORD{1'b0}};
      m_tlast <= 1'b0;
      gap <= 1'b0;
      gaps <= 32'd0;
      expected_seq <= initial_seq;
      req_valid <= 1'b0;
      req_seq <= 64'd0;
      req_count <= 16'd0;
      abandon <= 1'b0;
      requests <= 32'd0;
      abandoned <= 32'd0;
      req_pending <= 1'b0;
      req_timer <= 10'd0;
      force_accept <= 1'b0;
    end else begin
      gap <= 1'b0;
      abandon <= 1'b0;

      // ---------------- input capture ----------------
      if (a_first) begin
        in_a <= 1'b1;
        sa   <= a_seq;
        ca   <= a_count;
      end
      if (a_take) begin
        if (disc_a) begin
          if (a_tlast) begin disc_a <= 1'b0; dropped_a <= dropped_a + 32'd1; end
        end else if (a_first) begin
          mem_a[0] <= a_tdata;
          kep_a[0] <= a_tkeep;
          lst_a[0] <= a_tlast;
          wa_a <= 8'd1;
          if (a_tlast) begin
            in_a   <= 1'b0;
            full_a <= 1'b1;
            frames_a <= frames_a + 32'd1;
            wait_a <= 16'd0;
          end
        end else begin
          mem_a[wa_a[6:0]] <= a_tdata;
          kep_a[wa_a[6:0]] <= a_tkeep;
          lst_a[wa_a[6:0]] <= a_tlast;
          wa_a <= wa_a + 8'd1;
          if (a_tlast) begin
            in_a   <= 1'b0;
            full_a <= 1'b1;
            frames_a <= frames_a + 32'd1;
            wait_a <= 16'd0;
          end else if (wa_a == MAX_WORDS - 1) begin
            disc_a <= 1'b1;
            in_a   <= 1'b0;
            overflows <= overflows + 32'd1;
          end
        end
      end

      if (b_first) begin
        in_b <= 1'b1;
        sb   <= b_seq;
        cb   <= b_count;
      end
      if (b_take) begin
        if (disc_b) begin
          if (b_tlast) begin disc_b <= 1'b0; dropped_b <= dropped_b + 32'd1; end
        end else if (b_first) begin
          mem_b[0] <= b_tdata;
          kep_b[0] <= b_tkeep;
          lst_b[0] <= b_tlast;
          wa_b <= 8'd1;
          if (b_tlast) begin
            in_b   <= 1'b0;
            full_b <= 1'b1;
            frames_b <= frames_b + 32'd1;
            wait_b <= 16'd0;
          end
        end else begin
          mem_b[wa_b[6:0]] <= b_tdata;
          kep_b[wa_b[6:0]] <= b_tkeep;
          lst_b[wa_b[6:0]] <= b_tlast;
          wa_b <= wa_b + 8'd1;
          if (b_tlast) begin
            in_b   <= 1'b0;
            full_b <= 1'b1;
            frames_b <= frames_b + 32'd1;
            wait_b <= 16'd0;
          end else if (wa_b == MAX_WORDS - 1) begin
            disc_b <= 1'b1;
            in_b   <= 1'b0;
            overflows <= overflows + 32'd1;
          end
        end
      end

      if (only_a && !decide) wait_a <= wait_a + 16'd1;
      if (only_b && !decide) wait_b <= wait_b + 16'd1;

      // ---------------- decision + stream ----------------
      case (state)
        ST_IDLE: begin
          m_tvalid <= 1'b0;
          if (decide) begin
            if (recovery_en && win_gap && !force_accept) begin
              // Request the missing range and drop the out-of-order frames so
              // the replay can use the buffers.
              req_valid   <= 1'b1;
              req_seq     <= expected_seq;
              req_count   <= (miss > 64'd65535) ? 16'hFFFF : miss[15:0];
              requests    <= requests + 32'd1;
              req_pending <= 1'b1;
              req_timer   <= 10'd0;
              full_a      <= 1'b0;
              full_b      <= 1'b0;
              dropped_a   <= dropped_a + 32'd1;
              dropped_b   <= dropped_b + 32'd1;
              gaps        <= gaps + 32'd1;
              gap         <= 1'b1;
            end else begin
              win_a <= pick_a;
              ra    <= 8'd0;
              state <= ST_STREAM;
              if (pick_a) begin
                full_b <= 1'b0;
                dropped_b <= dropped_b + 32'd1;
              end else begin
                full_a <= 1'b0;
                dropped_a <= dropped_a + 32'd1;
              end
              if (win_gap) begin
                gap <= 1'b1;
                gaps <= gaps + 32'd1;
              end
              if (force_accept) begin
                abandon      <= 1'b1;
                abandoned    <= abandoned + 32'd1;
                force_accept <= 1'b0;
              end
              if (req_pending) begin
                req_pending <= 1'b0;
                req_valid   <= 1'b0;
              end
              expected_seq <= win_seq + {48'd0, win_cnt};
            end
          end
          if (req_pending && !decide) begin
            if (req_timer >= REC_TIMEOUT) begin
              req_pending  <= 1'b0;
              req_valid    <= 1'b0;
              force_accept <= 1'b1;
              abandon      <= 1'b1;
              abandoned    <= abandoned + 32'd1;
            end else begin
              req_timer <= req_timer + 10'd1;
            end
          end
        end

        ST_STREAM: begin
          m_tvalid <= 1'b1;
          m_tdata  <= win_a ? mem_a[nra[6:0]] : mem_b[nra[6:0]];
          m_tkeep  <= win_a ? kep_a[nra[6:0]] : kep_b[nra[6:0]];
          m_tlast  <= win_a ? lst_a[nra[6:0]] : lst_b[nra[6:0]];
          if (m_tvalid && m_tready) begin
            if (m_tlast) begin
              m_tvalid <= 1'b0;
              m_tlast  <= 1'b0;
              if (win_a) full_a <= 1'b0; else full_b <= 1'b0;
              state <= ST_IDLE;
            end else begin
              ra <= nra;
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

`endif
