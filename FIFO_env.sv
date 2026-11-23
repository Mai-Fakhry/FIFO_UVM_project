package FIFO_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import FIFO_seq_item_pkg::*;
  import FIFO_config_pkg::*;
  import FIFO_agent_pkg::*;
  import FIFO_scoreboard_pkg::*;
  import FIFO_coverage_pkg::*;

class FIFO_env extends uvm_env;
  `uvm_component_utils(FIFO_env)

  FIFO_agent      agt;
  FIFO_scoreboard scb;
  FIFO_coverage   cov;
  FIFO_config     cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(FIFO_config)::get(this, "", "FIFO_cfg", cfg))
      `uvm_fatal("ENV", "FIFO_config not found in config_db")
    // hand the same config object down to the agent (and its children)
    uvm_config_db #(FIFO_config)::set(this, "agt*", "FIFO_cfg", cfg);

    agt = FIFO_agent::type_id::create("agt", this);
    if (cfg.has_scoreboard) scb = FIFO_scoreboard::type_id::create("scb", this);
    if (cfg.has_coverage)   cov = FIFO_coverage  ::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.has_scoreboard) agt.ap.connect(scb.imp);
    if (cfg.has_coverage)   agt.ap.connect(cov.analysis_export);
  endfunction
endclass

endpackage
