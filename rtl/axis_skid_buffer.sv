// ============================================================================
// File: rtl/axis_skid_buffer.sv
// Module: axis_skid_buffer
// Description: 2-entry elastic AXI4-Stream skid buffer. Holds tdata/tkeep/tlast
//              stable while tready is low and absorbs one beat of back-pressure.
//              This is the building block for the open MoldUDP64 multi-frame
//              back-pressure item (R1).
// ============================================================================
`timescale 1ns/1ps

`ifndef AXIS_SKID_BUFFER_SV
`define AXIS_SKID_BUFFER_SV

module axis_skid_buffer #(
  parameter DATA_WIDTH = 128,
  parameter BYTES_PER_WORD = DATA_WIDTH / 8
)(
  input  wire                        clk,
  input  wire                        rst_n,

  input  wire [DATA_WIDTH-1:0]       s_tdata,
  input  wire [BYTES_PER_WORD-1:0]   s_tkeep,
  input  wire                        s_tvalid,
  input  wire                        s_tlast,
  output wire                        s_tready,

  output wire [DATA_WIDTH-1:0]       m_tdata,
  output wire [BYTES_PER_WORD-1:0]   m_tkeep,
  output wire                        m_tvalid,
  output wire                        m_tlast,
  input  wire                        m_tready,

  output wire [1:0]                  occupancy
);

  reg [DATA_WIDTH-1:0]     data0, data1;
  reg [BYTES_PER_WORD-1:0] keep0, keep1;
  reg                      last0, last1;
  reg                      valid0, valid1;

  assign s_tready  = !valid1 || m_tready;
  assign m_tvalid  = valid0;
  assign m_tdata   = data0;
  assign m_tkeep   = keep0;
  assign m_tlast   = last0;
  assign occupancy = {1'b0, valid0} + {1'b0, valid1};

  wire consume = valid0 && m_tready;
  wire append  = s_tvalid && s_tready;

  always @(posedge clk) begin
    if (!rst_n) begin
      valid0 <= 1'b0; valid1 <= 1'b0;
      data0 <= 0; data1 <= 0; keep0 <= 0; keep1 <= 0; last0 <= 0; last1 <= 0;
    end else begin
      if (consume) begin
        // Move entry 1 into the output slot.
        valid0 <= valid1;
        data0  <= data1;
        keep0  <= keep1;
        last0  <= last1;
        valid1 <= 1'b0;
      end
      if (append) begin
        if (consume) begin
          if (valid1) begin
            valid1 <= 1'b1;
            data1 <= s_tdata; keep1 <= s_tkeep; last1 <= s_tlast;
          end else begin
            valid0 <= 1'b1;
            data0 <= s_tdata; keep0 <= s_tkeep; last0 <= s_tlast;
          end
        end else if (!valid0) begin
          valid0 <= 1'b1;
          data0 <= s_tdata; keep0 <= s_tkeep; last0 <= s_tlast;
        end else if (!valid1) begin
          valid1 <= 1'b1;
          data1 <= s_tdata; keep1 <= s_tkeep; last1 <= s_tlast;
        end
      end
    end
  end


endmodule

`endif
