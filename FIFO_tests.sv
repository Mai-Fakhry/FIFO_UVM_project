package FIFO_tests_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;
  import FIFO_seq_item_pkg::*;
  import FIFO_config_pkg::*;
  import FIFO_sequencer_pkg::*;
  import FIFO_sequences_pkg::*;
  import FIFO_agent_pkg::*;
  import FIFO_env_pkg::*;

////////////////////////////////////////////////////////////////////////////////
// Tests.  Select with  +UVM_TESTNAME=<name>.
//   FIFO_base_test        builds the env, runs nothing (parent of all tests)
//   FIFO_write_only_test  reset -> write_only
//   FIFO_read_only_test   reset -> write_only -> read_only
//   FIFO_write_read_test  reset -> write_read
//   FIFO_flags_test       reset -> flags
//   FIFO_wrap_test        reset -> wrap
//   FIFO_reset_test       reset -> reset_mid
//   FIFO_random_test      reset -> random
//   FIFO_main_test        full regression: FIFO_main_sequence
////////////////////////////////////////////////////////////////////////////////
class FIFO_base_test extends uvm_test;
  `uvm_component_utils(FIFO_base_test)

  FIFO_env    env;
  FIFO_config cfg;

  function new(string name = "FIFO_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = FIFO_config::type_id::create("cfg");
    if (!uvm_config_db #(virtual FIFO_INTERFACE)::get(this, "", "FIFO_vif", cfg.vif))
      `uvm_fatal("TEST", "virtual interface 'FIFO_vif' not set by the top module")
    uvm_config_db #(FIFO_config)::set(this, "env*", "FIFO_cfg", cfg);
    env = FIFO_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  // children override this
  virtual task run_sequences();
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "test running");
    run_sequences();
    repeat (5) @(posedge cfg.vif.clk);      // let the last cycle reach the monitor / scoreboard
    phase.drop_objection(this, "test done");
  endtask

  // PASS / FAIL banner
  function void report_phase(uvm_phase phase);
    uvm_report_server srv = uvm_report_server::get_server();
    if (srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL) == 0)
      `uvm_info("RESULT", $sformatf("*** TEST PASSED : %s ***", get_type_name()), UVM_NONE)
    else
      `uvm_info("RESULT", $sformatf("*** TEST FAILED : %s (%0d errors) ***", get_type_name(),
                srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL)), UVM_NONE)
  endfunction

  // convenience
  protected task do_reset(int unsigned cycles = 2);
    FIFO_reset_sequence s = FIFO_reset_sequence::type_id::create("rst_seq");
    s.cycles = cycles;
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_write_only_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_write_only_test)
  function new(string name = "FIFO_write_only_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_write_only_sequence s = FIFO_write_only_sequence::type_id::create("wo_seq");
    do_reset();
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_read_only_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_read_only_test)
  function new(string name = "FIFO_read_only_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_write_only_sequence w = FIFO_write_only_sequence::type_id::create("wo_seq");
    FIFO_read_only_sequence  r = FIFO_read_only_sequence ::type_id::create("ro_seq");
    do_reset();
    r.num = 3;  r.start(env.agt.sqr);            // read an EMPTY fifo first -> underflow
    w.num = FIFO_DEPTH;  w.start(env.agt.sqr);   // fill exactly (no overflow)
    r.num = FIFO_DEPTH + 3;  r.start(env.agt.sqr); // drain + 3 more underflows
  endtask
endclass

class FIFO_write_read_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_write_read_test)
  function new(string name = "FIFO_write_read_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_write_read_sequence s = FIFO_write_read_sequence::type_id::create("wrrd_seq");
    do_reset();
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_flags_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_flags_test)
  function new(string name = "FIFO_flags_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_flags_sequence s = FIFO_flags_sequence::type_id::create("flg_seq");
    do_reset();
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_wrap_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_wrap_test)
  function new(string name = "FIFO_wrap_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_wrap_sequence s = FIFO_wrap_sequence::type_id::create("wrp_seq");
    do_reset();
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_reset_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_reset_test)
  function new(string name = "FIFO_reset_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_reset_mid_sequence s = FIFO_reset_mid_sequence::type_id::create("rstm_seq");
    do_reset();
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_random_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_random_test)
  function new(string name = "FIFO_random_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_random_sequence s = FIFO_random_sequence::type_id::create("rnd_seq");
    do_reset();
    s.num = cfg.num_random_cycles;
    s.start(env.agt.sqr);
  endtask
endclass

class FIFO_main_test extends FIFO_base_test;
  `uvm_component_utils(FIFO_main_test)
  function new(string name = "FIFO_main_test", uvm_component parent = null); super.new(name, parent); endfunction
  task run_sequences();
    FIFO_main_sequence s = FIFO_main_sequence::type_id::create("main_seq");
    s.num_random = cfg.num_random_cycles;
    s.start(env.agt.sqr);
  endtask
endclass

endpackage
