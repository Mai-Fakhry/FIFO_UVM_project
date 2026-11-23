package FIFO_monitor_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import FIFO_seq_item_pkg::*;
  import FIFO_config_pkg::*;

////////////////////////////////////////////////////////////////////////////////
// FIFO_monitor : passive. Samples the interface on EVERY rising clock edge and
//                broadcasts one FIFO_seq_item per cycle on its analysis port
//                (-> scoreboard and coverage collector).
//
//  Sampling in the Active region of the rising edge returns the values the DUT
//  itself sees at that edge: this cycle's inputs, and the outputs produced by the
//  previous edge (registered outputs) / current state (combinational flags).
////////////////////////////////////////////////////////////////////////////////
class FIFO_monitor extends uvm_monitor;
  `uvm_component_utils(FIFO_monitor)

  virtual FIFO_INTERFACE vif;
  FIFO_config            cfg;
  uvm_analysis_port #(FIFO_seq_item) ap;
  int unsigned           n_sampled;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(FIFO_config)::get(this, "", "FIFO_cfg", cfg))
      `uvm_fatal("MON", "FIFO_config not found in config_db")
    vif = cfg.vif;
    ap  = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    FIFO_seq_item t;
    forever begin
      @(posedge vif.clk);
      t = FIFO_seq_item::type_id::create("mon_item");   // new object each cycle
      t.rst_n       = vif.rst_n;
      t.wr_en       = vif.wr_en;
      t.rd_en       = vif.rd_en;
      t.data_in     = vif.data_in;
      t.data_out    = vif.data_out;
      t.wr_ack      = vif.wr_ack;
      t.overflow    = vif.overflow;
      t.full        = vif.full;
      t.empty       = vif.empty;
      t.almostfull  = vif.almostfull;
      t.almostempty = vif.almostempty;
      t.underflow   = vif.underflow;
      n_sampled++;
      `uvm_info("MON", {"sampled: ", t.convert2string()}, UVM_DEBUG)
      ap.write(t);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("MON", $sformatf("cycles sampled=%0d", n_sampled), UVM_LOW)
  endfunction
endclass

endpackage
