// ============================================================================
// File: rtl/itch_top_of_book.sv
// Module: itch_top_of_book
// Description: Locate-indexed top of book for decoded ITCH 5.0 events.
//
//   Handles: A/F add, E/C execute, X cancel, D delete, U replace, P/Q trade.
//   Maintains per-locate best bid/ask price + shares, last trade and volume.
//
//   Design: a 4-way set-associative order table (64 sets x 4 ways, index =
//   ref[5:0]) plus a small per-locate price-level table (16 bid + 16 ask
//   levels). Adding or removing an order updates the level directly, so there
//   is no rescan and the input never stalls. The BBO is a 16-way max/min
//   reduction over the level table, two cycles behind the event.
//
//   Limits (documented, counted):
//     * max 16 distinct price levels per locate per side (level_overflow);
//     * max 4 live orders per 64-ref window / 256 orders total (drops_overflow);
//     * 16 locates (direct-mapped; aliasing reinitialises that slot).
// ============================================================================
`ifndef ITCH_TOP_OF_BOOK_SV
`define ITCH_TOP_OF_BOOK_SV

`include "itch_pkg.sv"

module itch_top_of_book #(
  parameter ORDERS  = 256,
  parameter LOCATES = 16,
  parameter LEVELS  = 16
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

  // Registered top of book for the event's locate (2 cycles after the event)
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
  output reg  [31:0]                 level_overflow,
  output reg  [31:0]                 rescans,        // kept for ABI compat; always 0
  output wire                        busy            // always 0 (no stall)
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

  localparam ORD_AW = (ORDERS <= 1) ? 1 : $clog2(ORDERS);
  localparam LVL_N  = LOCATES * LEVELS;
  localparam LVL_AW = (LVL_N <= 1) ? 1 : $clog2(LVL_N);
  localparam LOC_AW = (LOCATES <= 1) ? 1 : $clog2(LOCATES);
  localparam [ORD_AW-1:0] ORD_LAST = {ORD_AW{1'b1}};
  localparam [LVL_AW-1:0] LVL_LAST = {LVL_AW{1'b1}};
  localparam [LOC_AW-1:0] LOC_LAST = {LOC_AW{1'b1}};
  // --------------------------------------------------------------------------
  // Order store
  // --------------------------------------------------------------------------
  reg [63:0] ord_ref    [0:ORDERS-1];
  reg [7:0]  ord_side   [0:ORDERS-1];
  reg [31:0] ord_price  [0:ORDERS-1];
  reg [63:0] ord_shares [0:ORDERS-1];
  reg        ord_valid  [0:ORDERS-1];

  // --------------------------------------------------------------------------
  // Price-level tables: per locate, LEVELS bid and LEVELS ask levels
  // --------------------------------------------------------------------------
  reg        lb_valid  [0:LOCATES*LEVELS-1];
  reg [31:0] lb_price  [0:LOCATES*LEVELS-1];
  reg [63:0] lb_shares [0:LOCATES*LEVELS-1];
  reg        la_valid  [0:LOCATES*LEVELS-1];
  reg [31:0] la_price  [0:LOCATES*LEVELS-1];
  reg [63:0] la_shares [0:LOCATES*LEVELS-1];

  // Last trade / volume per locate
  reg [31:0] last_p [0:LOCATES-1];
  reg [63:0] last_s [0:LOCATES-1];
  reg [63:0] vol    [0:LOCATES-1];

  wire [3:0] loc_idx = s_locate[3:0];

  // 4-way set-associative lookup: set = ref[5:0], 64 sets x 4 ways.
  // Four parallel compares replace the previous 256-way compare bank.
  wire [5:0] ord_set  = s_order_ref[5:0];
  wire [7:0] ord_base = {ord_set, 2'b00};

  reg        found;
  reg [7:0]  found_idx;
  reg        free_found;
  reg [7:0]  free_idx;
  always @(*) begin
    found      = 1'b0;
    found_idx  = ord_base;
    free_found = 1'b0;
    free_idx   = ord_base;

    if (ord_valid[ord_base] && ord_ref[ord_base] == s_order_ref) begin
      found = 1'b1; found_idx = ord_base;
    end
    if (ord_valid[ord_base+1] && ord_ref[ord_base+1] == s_order_ref) begin
      found = 1'b1; found_idx = ord_base + 8'd1;
    end
    if (ord_valid[ord_base+2] && ord_ref[ord_base+2] == s_order_ref) begin
      found = 1'b1; found_idx = ord_base + 8'd2;
    end
    if (ord_valid[ord_base+3] && ord_ref[ord_base+3] == s_order_ref) begin
      found = 1'b1; found_idx = ord_base + 8'd3;
    end

    if (!ord_valid[ord_base]) begin
      free_found = 1'b1; free_idx = ord_base;
    end else if (!ord_valid[ord_base+1]) begin
      free_found = 1'b1; free_idx = ord_base + 8'd1;
    end else if (!ord_valid[ord_base+2]) begin
      free_found = 1'b1; free_idx = ord_base + 8'd2;
    end else if (!ord_valid[ord_base+3]) begin
      free_found = 1'b1; free_idx = ord_base + 8'd3;
    end
  end

  // --------------------------------------------------------------------------
  // Level search helpers (combinational)
  // --------------------------------------------------------------------------
  integer j;
  reg        add_found;   reg [4:0] add_slot;
  reg        add_free;    reg [4:0] add_free_slot;
  reg        rem_found;   reg [4:0] rem_slot;

  wire ev_bid  = (s_side == 8'h42);
  wire old_bid = (ord_side[found_idx] == 8'h42);

  always @(*) begin
    add_found     = 1'b0;
    add_slot      = 5'd0;
    add_free      = 1'b0;
    add_free_slot = 5'd0;
    for (j = 0; j < LEVELS; j = j + 1) begin
      if (ev_bid ? (lb_valid[loc_idx*LEVELS+j] && lb_price[loc_idx*LEVELS+j] == s_price)
                 : (la_valid[loc_idx*LEVELS+j] && la_price[loc_idx*LEVELS+j] == s_price)) begin
        add_found = 1'b1;
        add_slot  = j[4:0];
      end
      if (ev_bid ? !lb_valid[loc_idx*LEVELS+j] : !la_valid[loc_idx*LEVELS+j]) begin
        add_free      = 1'b1;
        add_free_slot = j[4:0];
      end
    end
  end

  always @(*) begin
    rem_found = 1'b0;
    rem_slot  = 5'd0;
    for (j = 0; j < LEVELS; j = j + 1) begin
      if (old_bid ? (lb_valid[loc_idx*LEVELS+j] && lb_price[loc_idx*LEVELS+j] == ord_price[found_idx])
                  : (la_valid[loc_idx*LEVELS+j] && la_price[loc_idx*LEVELS+j] == ord_price[found_idx])) begin
        rem_found = 1'b1;
        rem_slot  = j[4:0];
      end
    end
  end

  // Amount removed from the level: the whole order for D/U, clamped for E/C/X.
  wire [63:0] rm_amt = (s_msg_type == T_DELETE || s_msg_type == T_REPLACE) ?
                       ord_shares[found_idx] :
                       (s_shares > ord_shares[found_idx] ? ord_shares[found_idx] : s_shares);

  wire same_level = found && rem_found && add_found &&
                    (old_bid == ev_bid) &&
                    (ord_price[found_idx] == s_price) &&
                    (rem_slot == add_slot);

  // --------------------------------------------------------------------------
  // BBO reduction over the previous event's locate
  // --------------------------------------------------------------------------
  reg         p_valid;
  reg [3:0]   p_idx;
  reg [15:0]  p_locate;
  reg [31:0]  r_bid_p; reg [63:0] r_bid_s;
  reg [31:0]  r_ask_p; reg [63:0] r_ask_s;

  always @(*) begin
    r_bid_p = 32'd0;
    r_bid_s = 64'd0;
    r_ask_p = 32'hFFFF_FFFF;
    r_ask_s = 64'd0;
    for (j = 0; j < LEVELS; j = j + 1) begin
      if (lb_valid[p_idx*LEVELS+j]) begin
        if (lb_price[p_idx*LEVELS+j] > r_bid_p) begin
          r_bid_p = lb_price[p_idx*LEVELS+j];
          r_bid_s = lb_shares[p_idx*LEVELS+j];
        end else if (lb_price[p_idx*LEVELS+j] == r_bid_p) begin
          r_bid_s = r_bid_s + lb_shares[p_idx*LEVELS+j];
        end
      end
      if (la_valid[p_idx*LEVELS+j]) begin
        if (la_price[p_idx*LEVELS+j] < r_ask_p) begin
          r_ask_p = la_price[p_idx*LEVELS+j];
          r_ask_s = la_shares[p_idx*LEVELS+j];
        end else if (la_price[p_idx*LEVELS+j] == r_ask_p) begin
          r_ask_s = r_ask_s + la_shares[p_idx*LEVELS+j];
        end
      end
    end
  end

  assign s_ready = init_done;
  assign busy    = 1'b0;

  // --------------------------------------------------------------------------
  // Init + event processing
  // --------------------------------------------------------------------------
  localparam [1:0] PH_ORD = 2'd0;
  localparam [1:0] PH_BID = 2'd1;
  localparam [1:0] PH_ASK = 2'd2;
  localparam [1:0] PH_TRD = 2'd3;

  reg [1:0]       init_phase;
  reg [ORD_AW-1:0] ord_i;
  reg [LVL_AW-1:0] lvl_i;
  reg [LOC_AW-1:0] trd_i;
  reg             init_done;

  always @(posedge clk) begin
    if (!rst_n) begin
      init_phase     <= PH_ORD;
      ord_i          <= {ORD_AW{1'b0}};
      lvl_i          <= {LVL_AW{1'b0}};
      trd_i          <= {LOC_AW{1'b0}};
      init_done      <= 1'b0;
      p_valid        <= 1'b0;
      p_idx          <= 4'd0;
      p_locate       <= 16'd0;
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
      level_overflow <= 32'd0;
      rescans        <= 32'd0;
    end else if (!init_done) begin
      // Clear one table element per cycle (portable across Verilator versions).
      case (init_phase)
        PH_ORD: begin
          ord_valid[ord_i]  <= 1'b0;
          ord_ref[ord_i]    <= 64'd0;
          ord_side[ord_i]   <= 8'd0;
          ord_price[ord_i]  <= 32'd0;
          ord_shares[ord_i] <= 64'd0;
          if (ord_i == ORD_LAST) begin
            init_phase <= PH_BID;
            ord_i      <= {ORD_AW{1'b0}};
          end else begin
            ord_i <= ord_i + 1'b1;
          end
        end
        PH_BID: begin
          lb_valid[lvl_i]  <= 1'b0;
          lb_price[lvl_i]  <= 32'd0;
          lb_shares[lvl_i] <= 64'd0;
          if (lvl_i == LVL_LAST) begin
            init_phase <= PH_ASK;
            lvl_i      <= {LVL_AW{1'b0}};
          end else begin
            lvl_i <= lvl_i + 1'b1;
          end
        end
        PH_ASK: begin
          la_valid[lvl_i]  <= 1'b0;
          la_price[lvl_i]  <= 32'hFFFF_FFFF;
          la_shares[lvl_i] <= 64'd0;
          if (lvl_i == LVL_LAST) begin
            init_phase <= PH_TRD;
            lvl_i      <= {LVL_AW{1'b0}};
          end else begin
            lvl_i <= lvl_i + 1'b1;
          end
        end
        default: begin
          last_p[trd_i] <= 32'd0;
          last_s[trd_i] <= 64'd0;
          vol[trd_i]    <= 64'd0;
          if (trd_i == LOC_LAST) begin
            init_done  <= 1'b1;
            init_phase <= PH_ORD;
            trd_i      <= {LOC_AW{1'b0}};
          end else begin
            trd_i <= trd_i + 1'b1;
          end
        end
      endcase
    end else begin
      // Pipeline the event locate for the BBO reduction.
      p_valid  <= s_valid;
      p_idx    <= loc_idx;
      p_locate <= s_locate;

      m_valid <= 1'b0;
      if (p_valid) begin
        m_valid      <= 1'b1;
        m_locate     <= p_locate;
        m_bid_price  <= r_bid_p;
        m_bid_shares <= r_bid_s;
        m_ask_price  <= r_ask_p;
        m_ask_shares <= r_ask_s;
        m_last_price <= last_p[p_idx];
        m_last_shares<= last_s[p_idx];
        m_volume     <= vol[p_idx];
      end

      if (s_valid) begin
        if (s_msg_type == T_ADD || s_msg_type == T_ADD_MPID || s_msg_type == T_REPLACE) begin
          if (s_msg_type == T_REPLACE) begin
            // Remove the old order.
            if (found) begin
              ord_valid[found_idx] <= 1'b0;
              if (same_level) begin
                // Same price level: net update, no invalidate/add pair.
                if (ev_bid) begin
                  if ((lb_shares[loc_idx*LEVELS+add_slot] - rm_amt + s_shares) == 64'd0)
                    lb_valid[loc_idx*LEVELS+add_slot] <= 1'b0;
                  else
                    lb_valid[loc_idx*LEVELS+add_slot] <= 1'b1;
                  lb_shares[loc_idx*LEVELS+add_slot] <=
                      lb_shares[loc_idx*LEVELS+add_slot] - rm_amt + s_shares;
                end else begin
                  if ((la_shares[loc_idx*LEVELS+add_slot] - rm_amt + s_shares) == 64'd0)
                    la_valid[loc_idx*LEVELS+add_slot] <= 1'b0;
                  else
                    la_valid[loc_idx*LEVELS+add_slot] <= 1'b1;
                  la_shares[loc_idx*LEVELS+add_slot] <=
                      la_shares[loc_idx*LEVELS+add_slot] - rm_amt + s_shares;
                end
              end else if (rem_found) begin
                if (rm_amt >= (old_bid ? lb_shares[loc_idx*LEVELS+rem_slot]
                                       : la_shares[loc_idx*LEVELS+rem_slot])) begin
                  if (old_bid) lb_valid[loc_idx*LEVELS+rem_slot] <= 1'b0;
                  else         la_valid[loc_idx*LEVELS+rem_slot] <= 1'b0;
                end else begin
                  if (old_bid) lb_shares[loc_idx*LEVELS+rem_slot] <=
                      lb_shares[loc_idx*LEVELS+rem_slot] - rm_amt;
                  else         la_shares[loc_idx*LEVELS+rem_slot] <=
                      la_shares[loc_idx*LEVELS+rem_slot] - rm_amt;
                end
              end
            end
          end

          if (s_msg_type == T_REPLACE) begin
            if (found) begin
              ord_ref[found_idx]    <= s_new_ref;
              ord_side[found_idx]   <= s_side;
              ord_price[found_idx]  <= s_price;
              ord_shares[found_idx] <= s_shares;
              ord_valid[found_idx]  <= 1'b1;
            end else if (free_found) begin
              ord_valid[free_idx]  <= 1'b1;
              ord_ref[free_idx]    <= s_new_ref;
              ord_side[free_idx]   <= s_side;
              ord_price[free_idx]  <= s_price;
              ord_shares[free_idx] <= s_shares;
            end
          end else if (free_found) begin
            ord_valid[free_idx]  <= 1'b1;
            ord_ref[free_idx]    <= s_order_ref;
            ord_side[free_idx]   <= s_side;
            ord_price[free_idx]  <= s_price;
            ord_shares[free_idx] <= s_shares;
          end else begin
            drops_overflow <= drops_overflow + 32'd1;
          end

          if (!same_level) begin
            if (add_found) begin
              if (ev_bid) lb_shares[loc_idx*LEVELS+add_slot] <=
                  lb_shares[loc_idx*LEVELS+add_slot] + s_shares;
              else        la_shares[loc_idx*LEVELS+add_slot] <=
                  la_shares[loc_idx*LEVELS+add_slot] + s_shares;
            end else if (add_free) begin
              if (ev_bid) begin
                lb_valid[loc_idx*LEVELS+add_free_slot]  <= 1'b1;
                lb_price[loc_idx*LEVELS+add_free_slot]  <= s_price;
                lb_shares[loc_idx*LEVELS+add_free_slot] <= s_shares;
              end else begin
                la_valid[loc_idx*LEVELS+add_free_slot]  <= 1'b1;
                la_price[loc_idx*LEVELS+add_free_slot]  <= s_price;
                la_shares[loc_idx*LEVELS+add_free_slot] <= s_shares;
              end
            end else begin
              level_overflow <= level_overflow + 32'd1;
            end
          end
        end else if (s_msg_type == T_DELETE || s_msg_type == T_EXEC ||
                     s_msg_type == T_EXEC_PX || s_msg_type == T_CANCEL) begin
          if (found) begin
            if (s_msg_type == T_DELETE || ord_shares[found_idx] <= s_shares) begin
              ord_valid[found_idx] <= 1'b0;
            end else begin
              ord_shares[found_idx] <= ord_shares[found_idx] - s_shares;
            end
            if (rem_found) begin
              if (rm_amt >= (old_bid ? lb_shares[loc_idx*LEVELS+rem_slot]
                                     : la_shares[loc_idx*LEVELS+rem_slot])) begin
                if (old_bid) lb_valid[loc_idx*LEVELS+rem_slot] <= 1'b0;
                else         la_valid[loc_idx*LEVELS+rem_slot] <= 1'b0;
              end else begin
                if (old_bid) lb_shares[loc_idx*LEVELS+rem_slot] <=
                    lb_shares[loc_idx*LEVELS+rem_slot] - rm_amt;
                else         la_shares[loc_idx*LEVELS+rem_slot] <=
                    la_shares[loc_idx*LEVELS+rem_slot] - rm_amt;
              end
            end
          end
        end else if (s_msg_type == T_TRADE || s_msg_type == T_CROSS) begin
          last_p[loc_idx] <= s_price;
          last_s[loc_idx] <= s_shares;
          vol[loc_idx]    <= vol[loc_idx] + s_shares;
        end
      end
    end
  end

endmodule

`endif
