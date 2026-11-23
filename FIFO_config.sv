package FIFO_config_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

// Configuration object for the FIFO agent / environment.
class FIFO_config extends uvm_object;
  `uvm_object_utils(FIFO_config)

  virtual FIFO_INTERFACE vif;                    // handle to the physical interface
  uvm_active_passive_enum is_active = UVM_ACTIVE; // active: sequencer+driver+monitor
  bit has_scoreboard = 1;
  bit has_coverage   = 1;
  int unsigned num_random_cycles = 3000;          // length of FIFO_random_seq

  function new(string name = "FIFO_config");
    super.new(name);
  endfunction
endclass

endpackage
