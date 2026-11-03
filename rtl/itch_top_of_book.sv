// ============================================================================
// File: rtl/itch_top_of_book.sv
// Module: itch_top_of_book
// Description: Locate-indexed top of book for decoded ITCH 5.0 events.
//
//   Handles: A/F add, E/C execute, X cancel, D delete, U replace, P/Q trade.
//   Maintains per-locate best bid/ask price + shares, last trade and volume.
//
//   Implementation status: functional reference. The order table is a small
//   register array with a parallel ref lookup, and any event that touches the
//   best price triggers a multi-cycle rescan of that locate/side. The input is
//   stalled (`ready=0`) during a rescan, so no event is lost. A BRAM/hash order
//   store and a pipelined ladder are the timing-closed follow-up.
// ============================================================================
`ifndef ITCH_TOP_OF_BOOK_SV
`define ITCH_TOP_OF_BOOK_SV

`include "itch_pkg.sv"

module itch_top_of_book #(
  parameter ORDERS  = 256,
  parameter LOCATES = 16
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // Decoded event input (from itch_parser_core / itch_top registered egress)
  input  wire                        s_valid,
  input  wire [7:0]                  s_msg_type,
  input  wire [15:0]                 s_locate,
  input  wire [7:0]                  s_side,
  input  wire [63:0]                 s_order_ref,
  input  wire [63:0]                 s_new_ref,
  input  wire [31:0]                 s_price,
  input  wire [63:0]                 s_shares,
  output wire                        s_ready,

  // Registered top of book for the event's locate
  output reg                         m_valid,
  output reg  [15:0]                 m_locate,
  output reg  [31:0]                 m_bid_price,
  output reg  [63:0]                 m_bid_shares,
  output reg  [31:0]                 m_ask_price,
  output reg  [63:0]                 m_ask_shares,
  output reg  [31:0]                 m_last_price,
  output reg  [63:0]                 m_last_shares,
  output reg  [63:0]                 m_volume,

  // Observability
  output reg  [31:0]                 drops_overflow,
  output reg  [31:0]                 rescans,
  output reg                         busy
);

  localparam [7:0] T_ADD      = 8'h41; // A
  localparam [7:0] T_ADD_MPID = 8'h46; // F
  localparam [7:0] T_EXEC     = 8'h45; // E
  localparam [7:0] T_EXEC_PX  = 8'h43; // C
  localparam [7:0] T_CANCEL   = 8'h58; // X
  localparam [7:0] T_DELETE   = 8'h44; // D
  localparam [7:0] T_REPLACE  = 8'h55; // U
  localparam [7:0] T_TRADE    = 8'h50; // P
  localparam [7:0] T_CROSS    = 8'h51; // Q

  // --------------------------------------------------------------------------
  // Order store
  // --------------------------------------------------------------------------
  reg [63:0] ord_ref    [0:ORDERS-1];
  reg [15:0] ord_locate [0:ORDERS-1];
  reg [7:0]  ord_side   [0:ORDERS-1];
  reg [31:0] ord_price  [0:ORDERS-1];
  reg [63:0] ord_shares [0:ORDERS-1];
  reg        ord_valid  [0:ORDERS-1];

  // --------------------------------------------------------------------------
  // BBO cache (direct-mapped by locate)
  // --------------------------------------------------------------------------
  reg        bb_valid  [0:LOCATES-1];
  reg [15:0] bb_locate [0:LOCATES-1];
  reg [31:0] bb_bid_p  [0:LOCATES-1];
  reg [63:0] bb_bid_s  [0:LOCATES-1];
  reg [31:0] bb_ask_p  [0:LOCATES-1];
  reg [63:0] bb_ask_s  [0:LOCATES-1];
  reg [31:0] bb_last_p [0:LOCATES-1];
  reg [63:0] bb_last_s [0:LOCATES-1];
  reg [63:0] bb_vol    [0:LOCATES-1];

  wire [3:0] idx = s_locate[3:0];

  // Parallel lookup of the referenced order.
  integer i;
  reg        found;
  reg [7:0]  found_idx;
  reg        free_found;
  reg [7:0]  free_idx;
  always @(*) begin
    found      = 1'b0;
    found_idx  = 8'd0;
    free_found = 1'b0;
    free_idx   = 8'd0;
    for (i = ORDERS - 1; i >= 0; i = i - 1) begin
      if (ord_valid[i] && ord_ref[i] == s_order_ref) begin
        found     = 1'b1;
        found_idx = i[7:0];
      end
      if (!ord_valid[i]) begin
        free_found = 1'b1;
        free_idx   = i[7:0];
      end
    end
  end

  // --------------------------------------------------------------------------
  // Event processing
  // --------------------------------------------------------------------------
  localparam [1:0] ST_IDLE   = 2'd0;
  localparam [1:0] ST_DONE   = 2'd1;
  localparam [1:0] ST_RESCAN = 2'd2;

  reg [1:0]  state;
  reg [8:0]  init_i;
  reg        init_done;
  reg [3:0]  pend_idx;
  reg [15:0] pend_locate;
  reg [15:0] rs_locate;
  reg        rs_bid;
  reg [8:0]  rs_i;
  reg [31:0] rs_best_p;
  reg [63:0] rs_best_s;

  wire is_add   = (s_msg_type == T_ADD) || (s_msg_type == T_ADD_MPID);
  wire is_exec  = (s_msg_type == T_EXEC) || (s_msg_type == T_EXEC_PX);
  wire is_del   = (s_msg_type == T_DELETE);
  wire is_cxl   = (s_msg_type == T_CANCEL);
  wire is_repl  = (s_msg_type == T_REPLACE);
  wire is_trade = (s_msg_type == T_TRADE) || (s_msg_type == T_CROSS);

  // The stored side is authoritative: E/C/X/D carry no side field.
  wire        ord_is_bid = (ord_side[found_idx] == 8'h42);
  wire        at_bid = found && bb_valid[idx] && bb_locate[idx] == s_locate &&
                       ord_is_bid && ord_price[found_idx] == bb_bid_p[idx];
  wire        at_ask = found && bb_valid[idx] && bb_locate[idx] == s_locate &&
                       !ord_is_bid && ord_price[found_idx] == bb_ask_p[idx];
  wire        touch_bbo = found && (at_bid || at_ask);
  wire        need_rescan = touch_bbo && (is_del || is_exec || is_cxl || is_repl);

  assign s_ready = init_done && (state == ST_IDLE);

  always @(posedge clk) begin
    if (!rst_n) begin
      state          <= ST_IDLE;
      busy           <= 1'b0;
      m_valid        <= 1'b0;
      m_locate       <= 16'd0;
      m_bid_price    <= 32'd0;
      m_bid_shares   <= 64'd0;
      m_ask_price    <= 32'hFFFF_FFFF;
      m_ask_shares   <= 64'd0;
      m_last_price   <= 32'd0;
      m_last_shares  <= 64'd0;
      m_volume       <= 64'd0;
      drops_overflow <= 32'd0;
      rescans        <= 32'd0;
      init_i         <= 9'd0;
      init_done      <= 1'b0;
      pend_idx       <= 4'd0;
      pend_locate    <= 16'd0;
      rs_locate      <= 16'd0;
      rs_bid         <= 1'b1;
      rs_i           <= 9'd0;
      rs_best_p      <= 32'd0;
      rs_best_s      <= 64'd0;
    end else if (!init_done) begin
      // Clear the tables one entry per cycle. A for-loop reset with nonblocking
      // assignments is not portable across Verilator versions.
      if (init_i < ORDERS) begin
        ord_valid[init_i[7:0]]  <= 1'b0;
        ord_ref[init_i[7:0]]    <= 64'd0;
        ord_locate[init_i[7:0]] <= 16'd0;
        ord_side[init_i[7:0]]   <= 8'd0;
        ord_price[init_i[7:0]]  <= 32'd0;
        ord_shares[init_i[7:0]] <= 64'd0;
      end else if (init_i < ORDERS + LOCATES) begin
        bb_valid[init_i[3:0]]  <= 1'b0;
        bb_locate[init_i[3:0]] <= 16'd0;
        bb_bid_p[init_i[3:0]]  <= 32'd0;
        bb_bid_s[init_i[3:0]]  <= 64'd0;
        bb_ask_p[init_i[3:0]]  <= 32'hFFFF_FFFF;
        bb_ask_s[init_i[3:0]]  <= 64'd0;
        bb_last_p[init_i[3:0]] <= 32'd0;
        bb_last_s[init_i[3:0]] <= 64'd0;
        bb_vol[init_i[3:0]]    <= 64'd0;
      end
      if (init_i == ORDERS + LOCATES - 1) begin
        init_done <= 1'b1;
        init_i    <= 9'd0;
      end else begin
        init_i <= init_i + 9'd1;
      end
    end else begin
      m_valid <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (s_valid) begin
            pend_idx    <= idx;
            pend_locate <= s_locate;

            // Lazily initialise the locate cache.
            if (!bb_valid[idx] || bb_locate[idx] != s_locate) begin
              bb_valid[idx]  <= 1'b1;
              bb_locate[idx] <= s_locate;
              bb_bid_p[idx]  <= 32'd0;
              bb_bid_s[idx]  <= 64'd0;
              bb_ask_p[idx]  <= 32'hFFFF_FFFF;
              bb_ask_s[idx]  <= 64'd0;
              bb_last_p[idx] <= 32'd0;
              bb_last_s[idx] <= 64'd0;
              bb_vol[idx]    <= 64'd0;
            end

            if (is_add) begin
              if (!free_found) begin
                drops_overflow <= drops_overflow + 32'd1;
              end else begin
                ord_valid[free_idx]  <= 1'b1;
                ord_ref[free_idx]    <= s_order_ref;
                ord_locate[free_idx] <= s_locate;
                ord_side[free_idx]   <= s_side;
                ord_price[free_idx]  <= s_price;
                ord_shares[free_idx] <= s_shares;
                if (s_side == 8'h42) begin
                  if (s_price > bb_bid_p[idx]) begin
                    bb_bid_p[idx] <= s_price;
                    bb_bid_s[idx] <= s_shares;
                  end else if (s_price == bb_bid_p[idx]) begin
                    bb_bid_s[idx] <= bb_bid_s[idx] + s_shares;
                  end
                end else begin
                  if (s_price < bb_ask_p[idx]) begin
                    bb_ask_p[idx] <= s_price;
                    bb_ask_s[idx] <= s_shares;
                  end else if (s_price == bb_ask_p[idx]) begin
                    bb_ask_s[idx] <= bb_ask_s[idx] + s_shares;
                  end
                end
              end
            end else if (is_repl) begin
              if (found) begin
                // Reuse the slot for the new order.
                ord_ref[found_idx]    <= s_new_ref;
                ord_locate[found_idx] <= s_locate;
                ord_side[found_idx]   <= s_side;
                ord_price[found_idx]  <= s_price;
                ord_shares[found_idx] <= s_shares;
                ord_valid[found_idx]  <= 1'b1;
              end else if (free_found) begin
                ord_valid[free_idx]  <= 1'b1;
                ord_ref[free_idx]    <= s_new_ref;
                ord_locate[free_idx] <= s_locate;
                ord_side[free_idx]   <= s_side;
                ord_price[free_idx]  <= s_price;
                ord_shares[free_idx] <= s_shares;
              end else begin
                drops_overflow <= drops_overflow + 32'd1;
              end
              // The new price may become the best (or join the best level).
              // If the old order touched the BBO, the rescan below recomputes
              // the exact level and overwrites this provisional update.
              if (s_side == 8'h42) begin
                if (s_price > bb_bid_p[idx]) begin
                  bb_bid_p[idx] <= s_price;
                  bb_bid_s[idx] <= s_shares;
                end else if (s_price == bb_bid_p[idx]) begin
                  bb_bid_s[idx] <= bb_bid_s[idx] + s_shares;
                end
              end else begin
                if (s_price < bb_ask_p[idx]) begin
                  bb_ask_p[idx] <= s_price;
                  bb_ask_s[idx] <= s_shares;
                end else if (s_price == bb_ask_p[idx]) begin
                  bb_ask_s[idx] <= bb_ask_s[idx] + s_shares;
                end
              end
            end else if (is_del || is_exec || is_cxl) begin
              if (found) begin
                if (is_del || ord_shares[found_idx] <= s_shares) begin
                  ord_valid[found_idx] <= 1'b0;
                end else begin
                  ord_shares[found_idx] <= ord_shares[found_idx] - s_shares;
                end
              end
            end else if (is_trade) begin
              bb_last_p[idx] <= s_price;
              bb_last_s[idx] <= s_shares;
              bb_vol[idx]    <= bb_vol[idx] + s_shares;
            end

            if (need_rescan) begin
              rs_locate <= s_locate;
              rs_bid    <= ord_is_bid;
              rs_i      <= 9'd0;
              rs_best_p <= ord_is_bid ? 32'd0 : 32'hFFFF_FFFF;
              rs_best_s <= 64'd0;
              state     <= ST_RESCAN;
              busy      <= 1'b1;
            end else begin
              state <= ST_DONE;
            end
          end
        end

        ST_DONE: begin
          // Publish the now-updated cache (+1 cycle, after all writes land).
          m_valid      <= 1'b1;
          m_locate     <= pend_locate;
          m_bid_price  <= bb_bid_p[pend_idx];
          m_bid_shares <= bb_bid_s[pend_idx];
          m_ask_price  <= bb_ask_p[pend_idx];
          m_ask_shares <= bb_ask_s[pend_idx];
          m_last_price <= bb_last_p[pend_idx];
          m_last_shares<= bb_last_s[pend_idx];
          m_volume     <= bb_vol[pend_idx];
          state        <= ST_IDLE;
        end

        ST_RESCAN: begin
          if (rs_i < ORDERS) begin
            if (ord_valid[rs_i[7:0]] && ord_locate[rs_i[7:0]] == rs_locate &&
                (ord_side[rs_i[7:0]] == 8'h42) == rs_bid) begin
              if (rs_bid) begin
                if (ord_price[rs_i[7:0]] > rs_best_p) begin
                  rs_best_p <= ord_price[rs_i[7:0]];
                  rs_best_s <= ord_shares[rs_i[7:0]];
                end else if (ord_price[rs_i[7:0]] == rs_best_p) begin
                  rs_best_s <= rs_best_s + ord_shares[rs_i[7:0]];
                end
              end else begin
                if (ord_price[rs_i[7:0]] < rs_best_p) begin
                  rs_best_p <= ord_price[rs_i[7:0]];
                  rs_best_s <= ord_shares[rs_i[7:0]];
                end else if (ord_price[rs_i[7:0]] == rs_best_p) begin
                  rs_best_s <= rs_best_s + ord_shares[rs_i[7:0]];
                end
              end
            end
            rs_i <= rs_i + 9'd1;
          end else begin
            // rs_best now includes every entry in the table.
            if (rs_bid) begin
              bb_bid_p[rs_locate[3:0]] <= rs_best_p;
              bb_bid_s[rs_locate[3:0]] <= rs_best_s;
              m_bid_price  <= rs_best_p;
              m_bid_shares <= rs_best_s;
              m_ask_price  <= bb_ask_p[rs_locate[3:0]];
              m_ask_shares <= bb_ask_s[rs_locate[3:0]];
            end else begin
              bb_ask_p[rs_locate[3:0]] <= rs_best_p;
              bb_ask_s[rs_locate[3:0]] <= rs_best_s;
              m_ask_price  <= rs_best_p;
              m_ask_shares <= rs_best_s;
              m_bid_price  <= bb_bid_p[rs_locate[3:0]];
              m_bid_shares <= bb_bid_s[rs_locate[3:0]];
            end
            m_valid      <= 1'b1;
            m_locate     <= rs_locate;
            m_last_price <= bb_last_p[rs_locate[3:0]];
            m_last_shares<= bb_last_s[rs_locate[3:0]];
            m_volume     <= bb_vol[rs_locate[3:0]];
            rescans      <= rescans + 32'd1;
            busy         <= 1'b0;
            state        <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

`endif
