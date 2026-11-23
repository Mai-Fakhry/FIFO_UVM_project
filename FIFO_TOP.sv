////////////////////////////////////////////////////////////////////////////////
// FIFO_TOP : static top of the testbench.
//   - generates the clock, instantiates the interface and the DUT
//   - BINDs the assertion module FIFO_SVA into every FIFO instance
//   - publishes the virtual interface and starts UVM (run_test)
////////////////////////////////////////////////////////////////////////////////
`include "uvm_macros.svh"
module FIFO_TOP;
  import uvm_pkg::*;
  import shared_pkg::*;
  import FIFO_pkg::*;

  logic clk;
  initial begin
    clk = 0;
    forever #5 clk = ~clk;                 // 100 MHz (1 unit = 1 ns)
  end

  FIFO_INTERFACE FIFO_if (.clk(clk));

  FIFO fifo_dut (.fifo_1(FIFO_if.DUT));

  // -------- assertions: attached to the DUT, can see internal count / pointers
  bind FIFO FIFO_SVA #(.W(FIFO_WIDTH), .D(FIFO_DEPTH)) u_fifo_sva (
    .clk        (fifo_1.clk),
    .rst_n      (fifo_1.rst_n),
    .wr_en      (fifo_1.wr_en),
    .rd_en      (fifo_1.rd_en),
    .data_in    (fifo_1.data_in),
    .data_out   (fifo_1.data_out),
    .wr_ack     (fifo_1.wr_ack),
    .overflow   (fifo_1.overflow),
    .full       (fifo_1.full),
    .empty      (fifo_1.empty),
    .almostfull (fifo_1.almostfull),
    .almostempty(fifo_1.almostempty),
    .underflow  (fifo_1.underflow),
    .count      (count),
    .wr_ptr     (wr_ptr),
    .rd_ptr     (rd_ptr)
  );

  initial begin
    uvm_config_db #(virtual FIFO_INTERFACE)::set(null, "uvm_test_top", "FIFO_vif", FIFO_if);
    run_test();                            // test name from +UVM_TESTNAME
  end
endmodule
