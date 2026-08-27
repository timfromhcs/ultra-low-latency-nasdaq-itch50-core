// ============================================================================
// File: formal/itch_formal.sv
// Module: itch_formal (SymbiYosys Formal Verification Top)
// Description: SVA Assertions, Assumptions, and Proofs for NASDAQ ITCH 5.0 Core.
// ============================================================================

`include "itch_pkg.sv"
`include "itch_drop_gate.sv"
`include "itch_parser_core.sv"
`include "itch_shifter.sv"
`include "itch_top.sv"

module itch_formal (
  input  wire         clk,
  input  wire         formal_rst_n,
  input  wire [127:0] s_axis_tdata,
  input  wire         s_axis_tvalid,
  input  wire         s_axis_tlast
);

  // ------------------------------------------------------------------------
  // Reset Generation & Sequencing for Formal Analysis
  // ------------------------------------------------------------------------
  reg [3:0] reset_cnt = 4'd0;
  always @(posedge clk) begin
    if (reset_cnt < 4'd5)
      reset_cnt <= reset_cnt + 4'd1;
  end

  wire rst_n = (reset_cnt >= 4'd4) && formal_rst_n;

  // ------------------------------------------------------------------------
  // DUT Instantiation
  // ------------------------------------------------------------------------
  wire                        s_axis_tready;
  wire                        raw_order_valid;
  wire [451:0]                raw_order_data;
  wire [15:0]                 raw_stock_locate_pre_trigger;
  wire [7:0]                  raw_msg_length;
  wire                        raw_is_trade;
  wire                        raw_is_drop;
  wire                        raw_is_corrupt;
  wire [7:0]                  status_buf_count;

  wire                        m_axis_order_valid;
  wire [7:0]                  m_order_type;
  wire [15:0]                 m_stock_locate;
  wire [15:0]                 m_tracking_number;
  wire [47:0]                 m_timestamp;
  wire [63:0]                 m_order_ref_num;
  wire [63:0]                 m_new_order_ref_num;
  wire [7:0]                  m_side;
  wire [31:0]                 m_shares;
  wire [63:0]                 m_stock;
  wire [31:0]                 m_price;
  wire [63:0]                 m_match_number;
  wire [31:0]                 m_mpid;
  wire                        m_printable;
  wire                        m_is_trade;
  wire                        m_is_drop;
  wire                        m_error_corrupt;

  ultra_low_latency_nasdaq_itch50_cutthrough #(
    .DATA_WIDTH(128)
  ) u_dut (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .s_axis_tdata                (s_axis_tdata),
    .s_axis_tvalid               (s_axis_tvalid),
    .s_axis_tlast                (s_axis_tlast),
    .s_axis_tready               (s_axis_tready),
    .raw_order_valid             (raw_order_valid),
    .raw_order_data              (raw_order_data),
    .raw_stock_locate_pre_trigger(raw_stock_locate_pre_trigger),
    .raw_msg_length              (raw_msg_length),
    .raw_is_trade                (raw_is_trade),
    .raw_is_drop                 (raw_is_drop),
    .raw_is_corrupt              (raw_is_corrupt),
    .status_buf_count            (status_buf_count),
    .m_axis_order_valid          (m_axis_order_valid),
    .m_order_type                (m_order_type),
    .m_stock_locate              (m_stock_locate),
    .m_tracking_number           (m_tracking_number),
    .m_timestamp                 (m_timestamp),
    .m_order_ref_num             (m_order_ref_num),
    .m_new_order_ref_num         (m_new_order_ref_num),
    .m_side                      (m_side),
    .m_shares                    (m_shares),
    .m_stock                     (m_stock),
    .m_price                     (m_price),
    .m_match_number              (m_match_number),
    .m_mpid                      (m_mpid),
    .m_printable                 (m_printable),
    .m_is_trade                  (m_is_trade),
    .m_is_drop                   (m_is_drop),
    .m_error_corrupt             (m_error_corrupt)
  );

  // ------------------------------------------------------------------------
  // Formal Assumptions
  // ------------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      assume(!s_axis_tvalid);
    end
  end

  // ------------------------------------------------------------------------
  // Formal Invariant Assertions
  // ------------------------------------------------------------------------
  reg past_valid = 1'b0;
  always @(posedge clk) begin
    if (!rst_n) begin
      past_valid <= 1'b0;
    end else begin
      past_valid <= 1'b1;
    end
  end

  // Invariant 1: Direct L3 Pre-Trigger is mathematically identical to parsed Stock Locate
  always @(posedge clk) begin
    if (rst_n && raw_order_valid) begin
      assert(raw_stock_locate_pre_trigger == raw_order_data[443:428]);
    end
  end

  // Invariant 2: Registered 1-Cycle Latency Guarantee
  reg          p_raw_order_valid = 1'b0;
  reg [7:0]    p_raw_type = 8'd0;
  reg [15:0]   p_raw_locate = 16'd0;
  reg [31:0]   p_raw_shares = 32'd0;
  reg [31:0]   p_raw_price = 32'd0;
  reg          p_raw_is_trade = 1'b0;
  reg          p_raw_is_drop = 1'b0;
  reg          p_raw_is_corrupt = 1'b0;

  always @(posedge clk) begin
    if (!rst_n) begin
      p_raw_order_valid <= 1'b0;
      p_raw_type        <= 8'd0;
      p_raw_locate      <= 16'd0;
      p_raw_shares      <= 32'd0;
      p_raw_price       <= 32'd0;
      p_raw_is_trade    <= 1'b0;
      p_raw_is_drop     <= 1'b0;
      p_raw_is_corrupt  <= 1'b0;
    end else begin
      p_raw_order_valid <= raw_order_valid;
      p_raw_type        <= raw_order_data[451:444];
      p_raw_locate      <= raw_order_data[443:428];
      p_raw_shares      <= raw_order_data[227:196];
      p_raw_price       <= raw_order_data[131:100];
      p_raw_is_trade    <= raw_is_trade;
      p_raw_is_drop     <= raw_is_drop;
      p_raw_is_corrupt  <= raw_is_corrupt;
    end
  end

  always @(posedge clk) begin
    if (rst_n && past_valid) begin
      assert(m_axis_order_valid == p_raw_order_valid);
      if (m_axis_order_valid) begin
        assert(m_order_type    == p_raw_type);
        assert(m_stock_locate  == p_raw_locate);
        assert(m_shares        == p_raw_shares);
        assert(m_price         == p_raw_price);
        assert(m_is_trade      == p_raw_is_trade);
        assert(m_is_drop       == p_raw_is_drop);
        assert(m_error_corrupt == p_raw_is_corrupt);
      end
    end
  end

  // Invariant 3: Message Class Exclusivity (Trade vs Drop vs Corrupt)
  always @(posedge clk) begin
    if (rst_n && m_axis_order_valid) begin
      assert((m_is_trade + m_is_drop + m_error_corrupt) == 1'b1);
    end
  end

  // Invariant 4: Add Order Correct Semantic Decoding
  always @(posedge clk) begin
    if (rst_n && m_axis_order_valid && (m_order_type == `MSG_ADD_ORDER)) begin
      assert(m_is_trade == 1'b1);
      assert(m_is_drop  == 1'b0);
      assert(m_error_corrupt == 1'b0);
    end
  end

  // Invariant 5: System / Admin Message Drop Integrity
  always @(posedge clk) begin
    if (rst_n && m_axis_order_valid && 
       ((m_order_type == `MSG_SYSTEM_EVENT) || 
        (m_order_type == `MSG_STOCK_DIRECTORY) || 
        (m_order_type == `MSG_STOCK_TRADING_ACTION))) begin
      assert(m_is_drop == 1'b1);
      assert(m_is_trade == 1'b0);
      assert(m_error_corrupt == 1'b0);
    end
  end

  // Invariant 6: Deadlock Freedom & Flow Control
  always @(posedge clk) begin
    if (rst_n) begin
      if (status_buf_count <= 8'd112) begin
        assert(s_axis_tready == 1'b1);
      end
    end
  end

  // ------------------------------------------------------------------------
  // Cover Properties: Reachability of Critical Trading Paths
  // ------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      cover(m_axis_order_valid && (m_order_type == `MSG_ADD_ORDER));
      cover(m_axis_order_valid && (m_order_type == `MSG_ORDER_EXECUTED));
      cover(m_axis_order_valid && (m_order_type == `MSG_ORDER_CANCEL));
      cover(m_axis_order_valid && (m_order_type == `MSG_ORDER_DELETE));
      cover(m_axis_order_valid && (m_order_type == `MSG_SYSTEM_EVENT));
      cover(m_axis_order_valid && m_is_trade);
    end
  end

endmodule