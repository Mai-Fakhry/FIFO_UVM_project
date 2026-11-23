////////////////////////////////////////////////////////////////////////////////
// FIFO_INTERFACE : single physical interface between the UVM testbench and DUT
//  - DUT     : the view used by the FIFO RTL (unchanged from the SV project)
//  - DRV     : the view used by the UVM driver  (drives inputs, reads outputs)
//  - MON     : the view used by the UVM monitor (read-only on everything)
//
// Timing convention (race-free, same convention as the SV project):
//  * driver  changes inputs on the FALLING clock edge  (half a cycle of setup)
//  * monitor samples everything on the RISING clock edge, in the Active region,
//    i.e. BEFORE the DUT's non-blocking updates -> it sees exactly the values
//    the DUT sees at that edge (inputs of this cycle + registered outputs that
//    resulted from the previous edge).
////////////////////////////////////////////////////////////////////////////////
import shared_pkg::*;

interface FIFO_INTERFACE (input logic clk);

  logic [FIFO_WIDTH-1:0] data_in;
  logic                  rst_n, wr_en, rd_en;
  logic [FIFO_WIDTH-1:0] data_out;
  logic                  wr_ack, overflow;
  logic                  full, empty, almostfull, almostempty, underflow;

  modport DUT (
    input  clk, rst_n, data_in, wr_en, rd_en,
    output data_out, wr_ack, overflow, full, empty, almostfull, almostempty, underflow
  );

  modport DRV (
    input  clk,
    output rst_n, data_in, wr_en, rd_en,
    input  data_out, wr_ack, overflow, full, empty, almostfull, almostempty, underflow
  );

  modport MON (
    input clk, rst_n, data_in, wr_en, rd_en,
          data_out, wr_ack, overflow, full, empty, almostfull, almostempty, underflow
  );

endinterface
