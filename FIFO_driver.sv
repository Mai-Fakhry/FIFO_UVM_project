package FIFO_driver_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import FIFO_seq_item_pkg::*;
  import FIFO_config_pkg::*;

////////////////////////////////////////////////////////////////////////////////
// FIFO_driver : pulls FIFO_seq_item from the sequencer and wiggles the DUT pins
//               through the virtual interface, ONE ITEM PER CLOCK CYCLE.
//
//  * inputs are changed on the falling clock edge (half a cycle before the DUT
//    samples them on the rising edge)  -> no race, and reset is asserted/released
//    away from a clock edge so the DUT's ASYNCHRONOUS reset is genuinely exercised.
//  * if the sequencer has nothing ready the driver drives an IDLE cycle
//    (wr_en = rd_en = 0), so a finished sequence can never leave wr_en stuck at 1.
////////////////////////////////////////////////////////////////////////////////
class FIFO_driver extends uvm_driver #(FIFO_seq_item);
  `uvm_component_utils(FIFO_driver)

  virtual FIFO_INTERFACE vif;
  FIFO_config            cfg;
  int unsigned           n_driven, n_idle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(FIFO_config)::get(this, "", "FIFO_cfg", cfg))
      `uvm_fatal("DRV", "FIFO_config not found in config_db")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    FIFO_seq_item req;
    // power-on state: reset asserted, bus quiet (time 0)
    vif.rst_n   = 1'b0;
    vif.wr_en   = 1'b0;
    vif.rd_en   = 1'b0;
    vif.data_in = '0;

    forever begin
      @(negedge vif.clk);
      seq_item_port.try_next_item(req);
      if (req == null) begin
        drive_idle();
      end
      else begin
        drive_item(req);
        seq_item_port.item_done();
      end
    end
  endtask

  task drive_item(FIFO_seq_item req);
    vif.rst_n   = req.rst_n;
    vif.wr_en   = req.wr_en;
    vif.rd_en   = req.rd_en;
    vif.data_in = req.data_in;
    n_driven++;
    `uvm_info("DRV", {"drove: ", req.convert2string()}, UVM_DEBUG)
  endtask

  task drive_idle();
    vif.wr_en = 1'b0;      // rst_n and data_in keep their last value
    vif.rd_en = 1'b0;
    n_idle++;
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("DRV", $sformatf("items driven=%0d, idle cycles=%0d", n_driven, n_idle), UVM_LOW)
  endfunction
endclass

endpackage
