// ============================================================================
// File: rtl/moldudp64_depacketizer.sv
// Module: moldudp64_depacketizer
// Description: Removes MoldUDP64 per-message 2-byte length prefixes and emits
//              a pure ITCH byte stream. The front-end (moldudp64_frontend)
//              deliberately exports the raw Mold payload (headers stripped) so
//              this stage can be reused by other Mold-based protocols.
//
//   Throughput: up to BYTES_PER_WORD bytes/cycle; a 2-byte prefix costs one
//   extra cycle per message. For ITCH (~30 B average) this is <7% overhead.
//
//   Frame boundaries: `frame_start` accompanies the first accepted payload beat
//   and `frame_end` the last accepted beat of the Ethernet frame. `frame_end`
//   releases the stage, so trailing Ethernet padding can never deadlock it.
// ============================================================================
`ifndef MOLDUDp64_DEPACKETIZER_SV
`define MOLDUDp64_DEPACKETIZER_SV

`include "itch_pkg.sv"

module moldudp64_depacketizer #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8,
  parameter BUFFER_BYTES = 128
)(
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire [15:0]                 msg_count,
  input  wire                        frame_start,
  input  wire                        frame_end,

  input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
  input  wire [BYTES_PER_WORD-1:0]   s_axis_tkeep,
  input  wire                        s_axis_tvalid,
  output wire                        s_axis_tready,

  output reg  [DATA_WIDTH-1:0]       m_axis_tdata,
  output reg  [BYTES_PER_WORD-1:0]   m_axis_tkeep,
  output reg                         m_axis_tvalid,
  output reg                         m_axis_tlast,

  output reg  [15:0]                 msgs_left,
  output reg                         frame_done,
  output reg                         busy
);

  function automatic [7:0] keep_to_bytes(input [BYTES_PER_WORD-1:0] keep);
    integer i;
    begin
      keep_to_bytes = 0;
      for (i = 0; i < BYTES_PER_WORD; i = i + 1)
        if (keep[i]) keep_to_bytes = keep_to_bytes + 1;
    end
  endfunction

  function automatic [BYTES_PER_WORD*8-1:0] keep_to_mask(input [BYTES_PER_WORD-1:0] keep);
    integer i;
    begin
      for (i = 0; i < BYTES_PER_WORD; i = i + 1)
        keep_to_mask[i*8 +: 8] = {8{keep[i]}};
    end
  endfunction

  function automatic [DATA_WIDTH-1:0] byte_mask(input [7:0] n);
    begin
      byte_mask = ({24'd0, n} >= BYTES_PER_WORD) ? {DATA_WIDTH{1'b1}} :
                  (({{(DATA_WIDTH-1){1'b0}}, 1'b1} << (n*8)) - 1'b1);
    end
  endfunction

  reg [BUFFER_BYTES*8-1:0] store;
  reg [7:0]                count;
  reg [15:0]               msg_left;
  reg                      saw_frame_end;

  wire [7:0] in_bytes = (s_axis_tvalid && s_axis_tready) ? keep_to_bytes(s_axis_tkeep) : 8'd0;
  wire       in_accept = s_axis_tvalid && s_axis_tready;
  wire [DATA_WIDTH-1:0] in_masked = s_axis_tdata & keep_to_mask(s_axis_tkeep);

  assign s_axis_tready = ({24'd0, count} <= (BUFFER_BYTES - BYTES_PER_WORD));

  // Combinational consumption decision (one prefix or one data beat per cycle).
  reg  [7:0]  consume;
  reg         out_valid;
  reg  [7:0]  out_n;
  reg         start_prefix;
  reg         finish_msg;

  always @(*) begin
    consume      = 8'd0;
    out_valid    = 1'b0;
    out_n        = 8'd0;
    start_prefix = 1'b0;
    finish_msg   = 1'b0;

    if (msgs_left > 16'd0) begin
      if (msg_left == 16'd0) begin
        // Need the 2-byte length prefix.
        if (count >= 8'd2) begin
          consume      = 8'd2;
          start_prefix = 1'b1;
        end
      end else begin
        // Emit up to one AXI beat of message bytes.
        out_n = (msg_left >= 16'(BYTES_PER_WORD)) ? BYTES_PER_WORD[7:0] : msg_left[7:0];
        if (count >= out_n) begin
          out_valid = 1'b1;
          consume   = out_n;
          if (msg_left == {8'd0, out_n}) finish_msg = 1'b1;
        end
      end
    end
  end

  wire [15:0] prefix_len = {store[7:0], store[15:8]}; // big-endian at the window head
  wire [15:0] next_msg_left = start_prefix ? prefix_len : (msg_left - {8'd0, consume});
  wire [15:0] next_msgs_left = (finish_msg || (start_prefix && prefix_len == 16'd0)) ?
                               (msgs_left - 16'd1) : msgs_left;

  // Next buffer / count
  wire [BUFFER_BYTES*8-1:0] cleared = store & ~({{(BUFFER_BYTES*8-1){1'b0}}, 1'b1} << (count*8));
  wire [BUFFER_BYTES*8-1:0] shifted = cleared >> (consume*8);
  wire [7:0]                post_count = count - consume;
  wire [BUFFER_BYTES*8-1:0] appended = {{(BUFFER_BYTES*8-DATA_WIDTH){1'b0}}, in_masked}
                                       << (post_count*8);
  wire [BUFFER_BYTES*8-1:0] next_buf = shifted | (in_accept ? appended : {BUFFER_BYTES*8{1'b0}});
  wire [7:0]                next_count = post_count + (in_accept ? in_bytes : 8'd0);

  always @(posedge clk) begin
    if (!rst_n) begin
      store          <= {BUFFER_BYTES*8{1'b0}};
      count          <= 8'd0;
      msg_left       <= 16'd0;
      msgs_left      <= 16'd0;
      m_axis_tdata   <= {DATA_WIDTH{1'b0}};
      m_axis_tkeep   <= {BYTES_PER_WORD{1'b0}};
      m_axis_tvalid  <= 1'b0;
      m_axis_tlast   <= 1'b0;
      frame_done     <= 1'b0;
      busy           <= 1'b0;
      saw_frame_end  <= 1'b0;
    end else begin
      m_axis_tvalid <= out_valid;
      m_axis_tlast  <= 1'b0;
      frame_done    <= 1'b0;

      if (out_valid) begin
        m_axis_tdata <= store[DATA_WIDTH-1:0] & byte_mask(out_n);
        m_axis_tkeep <= ({24'd0, out_n} >= BYTES_PER_WORD) ? {BYTES_PER_WORD{1'b1}} :
                        (({{(BYTES_PER_WORD-1){1'b0}}, 1'b1} << out_n) - 1'b1);
        // End of the last message. The front-end's tlast is not cycle-aligned
        // with this beat because this stage buffers.
        m_axis_tlast <= (next_msgs_left == 16'd0) && (next_msg_left == 16'd0);
        if (next_msgs_left == 16'd0 && next_msg_left == 16'd0) frame_done <= 1'b1;
      end

      if (frame_start) begin
        busy          <= 1'b1;
        saw_frame_end <= 1'b0;
        msgs_left     <= msg_count;
        msg_left      <= 16'd0;
        // Keep a payload beat that arrives in the same cycle as frame_start.
        store         <= {{(BUFFER_BYTES*8-DATA_WIDTH){1'b0}}, in_masked};
        count         <= in_bytes;
      end else begin
        if (frame_end) saw_frame_end <= 1'b1;

        if (busy && (saw_frame_end || frame_end) && msgs_left == 16'd0 &&
            msg_left == 16'd0 && !m_axis_tvalid) begin
          // Input and output are both done: release the front-end.
          busy          <= 1'b0;
          saw_frame_end <= 1'b0;
          store         <= {BUFFER_BYTES*8{1'b0}};
          count         <= 8'd0;
        end else if (busy && msgs_left == 16'd0) begin
          // All messages are emitted but the Ethernet frame may still deliver
          // padding; discard it so the buffer cannot fill and deadlock.
          store <= {BUFFER_BYTES*8{1'b0}};
          count <= 8'd0;
        end else begin
          msgs_left <= next_msgs_left;
          msg_left  <= next_msg_left;
          store     <= next_buf;
          count     <= next_count;
        end
      end
    end
  end

endmodule

`endif
