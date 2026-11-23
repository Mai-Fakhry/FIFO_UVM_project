package FIFO_sequences_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;
  import FIFO_seq_item_pkg::*;

////////////////////////////////////////////////////////////////////////////////
// FIFO sequence library.
//
// The single "main sequence" of the SV project is split into focused sequences,
// each one with a verification goal (see the Verification Plan, section 3).
//
//   FIFO_base_sequence        helper API shared by all sequences
//   FIFO_reset_sequence       RST   : apply / release reset
//   FIFO_write_only_sequence  WR    : writes only  -> fill, full, overflow
//   FIFO_read_only_sequence   RD    : reads  only  -> drain, empty, underflow
//   FIFO_write_read_sequence  WRRD  : simultaneous wr+rd in empty / mid / full
//   FIFO_flags_sequence       FLAG  : almost-full / almost-empty / idle in each state
//   FIFO_wrap_sequence        WRAP  : pointer wrap-around + data integrity
//   FIFO_reset_mid_sequence   RSTM  : (async) reset hitting every FIFO state
//   FIFO_random_sequence      RAND  : constrained-random, phases with different bias
//   FIFO_main_sequence        ALL   : runs all of the above back to back
//
// All the directed sequences start with the assumption that the FIFO is EMPTY
// (the tests run FIFO_reset_sequence first), and each leaves it in a documented state.
////////////////////////////////////////////////////////////////////////////////

class FIFO_base_sequence extends uvm_sequence #(FIFO_seq_item);
  `uvm_object_utils(FIFO_base_sequence)

  function new(string name = "FIFO_base_sequence");
    super.new(name);
  endfunction

  // send ONE clock cycle of activity.
  //   mode  : "write_only" | "read_only" | "write_read" | "idle" | "in_reset" |
  //           "reset_traffic" | "random"
  //   wr_pct/rd_pct only matter for mode "random"
  protected task send(string mode, int unsigned wr_pct = 70, int unsigned rd_pct = 30,
                      int unsigned rst_pct = 98);
    FIFO_seq_item req = FIFO_seq_item::type_id::create("req");
    start_item(req);
    req.set_mode(mode);
    req.WR_EN_ON_DIST = wr_pct;
    req.RD_EN_ON_DIST = rd_pct;
    req.RST_N_ON_DIST = rst_pct;
    if (!req.randomize())
      `uvm_fatal(get_type_name(), $sformatf("randomize() failed in mode '%s'", mode))
    finish_item(req);
  endtask

  protected task send_n(int unsigned n, string mode, int unsigned wr_pct = 70, int unsigned rd_pct = 30);
    repeat (n) send(mode, wr_pct, rd_pct);
  endtask
endclass

//------------------------------------------------------------------------------
// RST : hold reset low for `cycles` clocks, then release it for one idle cycle.
//------------------------------------------------------------------------------
class FIFO_reset_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_reset_sequence)
  int unsigned cycles = 2;
  function new(string name = "FIFO_reset_sequence"); super.new(name); endfunction
  task body();
    `uvm_info(get_type_name(), $sformatf("reset for %0d cycles", cycles), UVM_MEDIUM)
    send_n(cycles, "in_reset");
    send("idle");                       // rst_n = 1, FIFO empty
  endtask
endclass

//------------------------------------------------------------------------------
// WR : writes only (rd_en = 0).  num = FIFO_DEPTH + 3 by default:
//        - DEPTH legal writes  -> count 0..DEPTH, full flag, almostfull flag
//        - 3 extra writes      -> write-while-full: overflow, wr_ack must stay low
// ends with: FIFO FULL
//------------------------------------------------------------------------------
class FIFO_write_only_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_write_only_sequence)
  int unsigned num = FIFO_DEPTH + 3;
  function new(string name = "FIFO_write_only_sequence"); super.new(name); endfunction
  task body();
    `uvm_info(get_type_name(), $sformatf("%0d write-only cycles", num), UVM_MEDIUM)
    send_n(num, "write_only");
  endtask
endclass

//------------------------------------------------------------------------------
// RD : reads only (wr_en = 0).  num = FIFO_DEPTH + 3 by default:
//        - drains a full FIFO (almostempty, empty), then 3 reads on empty -> underflow
// expects: FIFO FULL at start (run after write_only), ends EMPTY
//------------------------------------------------------------------------------
class FIFO_read_only_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_read_only_sequence)
  int unsigned num = FIFO_DEPTH + 3;
  function new(string name = "FIFO_read_only_sequence"); super.new(name); endfunction
  task body();
    `uvm_info(get_type_name(), $sformatf("%0d read-only cycles", num), UVM_MEDIUM)
    send_n(num, "read_only");
  endtask
endclass

//------------------------------------------------------------------------------
// WRRD : simultaneous write + read in the three interesting FIFO states
//   1. EMPTY   : only the write may happen (count 0 -> 1)
//   2. LEVEL 1 : both happen, count holds (almost-empty)
//   3. MID     : both happen, count holds
//   4. FULL    : only the read may happen (count D -> D-1), write is rejected (overflow)
//   5. ALMOSTFULL: both happen, count holds
// starts EMPTY, ends in ALMOSTFULL/FULL
//------------------------------------------------------------------------------
class FIFO_write_read_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_write_read_sequence)
  int unsigned num_mid = 12;          // streaming cycles at constant level
  function new(string name = "FIFO_write_read_sequence"); super.new(name); endfunction
  task body();
    int unsigned to_full;
    `uvm_info(get_type_name(), "wr+rd on EMPTY / almost-empty / mid / full / almost-full", UVM_MEDIUM)
    send("write_read");                         // (1) EMPTY: write only
    repeat (3) send("write_read");              // (2) level 1: pass-through
    send_n(FIFO_DEPTH/2, "write_only");         //     raise the level
    send_n(num_mid, "write_read");              // (3) MID: count holds
    to_full = FIFO_DEPTH - 1 - FIFO_DEPTH/2;
    send_n(to_full, "write_only");              //     -> FULL
    repeat (2) begin
      send("write_read");                       // (4) FULL: read only, write rejected -> overflow
      send("write_read");                       // (5) ALMOSTFULL: both
      send("write_only");                       //     back to FULL
    end
    send("idle");
  endtask
endclass

//------------------------------------------------------------------------------
// FLAG : directed corner cases of the status flags with idle / non-idle inputs
//   almostfull with wr=rd=0, full with wr=rd=0, almostempty with wr=rd=0,
//   empty with wr=rd=0, every state left in every possible direction.
// starts EMPTY, ends EMPTY
//------------------------------------------------------------------------------
class FIFO_flags_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_flags_sequence)
  function new(string name = "FIFO_flags_sequence"); super.new(name); endfunction
  task body();
    `uvm_info(get_type_name(), "almost-full / almost-empty / idle corners", UVM_MEDIUM)
    send_n(2, "idle");                                    // EMPTY + idle
    send_n(FIFO_DEPTH-1, "write_only");                   // -> ALMOSTFULL
    send_n(3, "idle");                                    // ALMOSTFULL + idle
    send("write_read");                                   // ALMOSTFULL + wr+rd (holds)
    send("write_only");                                   // -> FULL
    send_n(3, "idle");                                    // FULL + idle
    send("read_only");                                    // FULL -> ALMOSTFULL
    send("write_only");                                   // ALMOSTFULL -> FULL
    send_n(FIFO_DEPTH-1, "read_only");                    // -> ALMOSTEMPTY (1 left)
    send_n(3, "idle");                                    // ALMOSTEMPTY + idle
    send("write_read");                                   // ALMOSTEMPTY + wr+rd
    send("write_only");                                   // ALMOSTEMPTY -> 2 (MID)
    send("read_only");                                    // MID -> ALMOSTEMPTY
    send("read_only");                                    // ALMOSTEMPTY -> EMPTY
    send_n(2, "idle");                                    // EMPTY + idle
    send("read_only");                                    // EMPTY + read  (underflow)
    send("write_read");                                   // EMPTY + wr+rd (write only)
    send("read_only");                                    // drain it again
    send_n(2, "idle");
  endtask
endclass

//------------------------------------------------------------------------------
// WRAP : exercise pointer wrap-around and check data ORDER end to end
//   - ROUNDS x { fill DEPTH ; drain DEPTH } with fresh random data
//   - a shifted pattern (level != 0) so that wr_ptr/rd_ptr wrap at a non-zero offset
//   - sustained streaming (wr+rd every cycle) -> pointers wrap many times at constant level
// starts EMPTY, ends EMPTY
//------------------------------------------------------------------------------
class FIFO_wrap_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_wrap_sequence)
  int unsigned rounds = 3;
  function new(string name = "FIFO_wrap_sequence"); super.new(name); endfunction
  task body();
    `uvm_info(get_type_name(), "pointer wrap-around", UVM_MEDIUM)
    repeat (rounds) begin
      send_n(FIFO_DEPTH, "write_only");
      send_n(FIFO_DEPTH, "read_only");
    end
    send_n(3, "write_only");                              // offset the pointers (level 3)
    send_n(3*FIFO_DEPTH, "write_read");                   // 3 full laps at constant level
    send_n(3, "read_only");                               // drain the 3 left
    send_n(2, "idle");
  endtask
endclass

//------------------------------------------------------------------------------
// RSTM : reset applied while the FIFO is in each state / while traffic is on the bus
// starts EMPTY, ends EMPTY
//------------------------------------------------------------------------------
class FIFO_reset_mid_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_reset_mid_sequence)
  function new(string name = "FIFO_reset_mid_sequence"); super.new(name); endfunction

  task body();
    `uvm_info(get_type_name(), "reset hitting each FIFO state", UVM_MEDIUM)
    // reset while EMPTY, with write+read traffic on the bus
    send("reset_traffic");  send("idle");
    // reset while ALMOSTEMPTY (1 entry)
    send("write_only");     send("reset_traffic");  send("idle");
    // reset while MID
    send_n(4, "write_only"); send("reset_traffic"); send("idle");
    // reset while ALMOSTFULL
    send_n(FIFO_DEPTH-1, "write_only"); send("reset_traffic"); send("idle");
    // reset while FULL (a 2-cycle reset)
    send_n(FIFO_DEPTH, "write_only");   send("in_reset"); send("in_reset"); send("idle");
    // reset in the same cycle a write overflows
    send_n(FIFO_DEPTH, "write_only");   send("write_only"); send("reset_traffic"); send("idle");
    // after a reset the FIFO must be empty AND usable: write, read it back
    send_n(3, "write_only");  send_n(3, "read_only");  send_n(2, "idle");
  endtask
endclass

//------------------------------------------------------------------------------
// RAND : constrained random with 5 phases of different bias so that every
//        corner of the dist-constraints is visited (write-heavy, read-heavy,
//        balanced, both-high, reset-heavy).
//------------------------------------------------------------------------------
class FIFO_random_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_random_sequence)
  int unsigned num = 3000;            // total cycles
  function new(string name = "FIFO_random_sequence"); super.new(name); endfunction
  task body();
    int unsigned chunk = num / 5;
    `uvm_info(get_type_name(), $sformatf("%0d random cycles", num), UVM_MEDIUM)
    repeat (chunk) send("random", 70, 30);                  // SV-project default bias
    repeat (chunk) send("random", 20, 80);                  // read-heavy  (mostly empty)
    repeat (chunk) send("random", 50, 50);                  // balanced
    repeat (chunk) send("random", 90, 90);                  // both-high   (wr+rd collisions)
    repeat (chunk) send("random", 60, 40, 90);              // reset-heavy (10 % resets)
  endtask
endclass

//------------------------------------------------------------------------------
// ALL : the original "main sequence", now only a composition of the above
//------------------------------------------------------------------------------
class FIFO_main_sequence extends FIFO_base_sequence;
  `uvm_object_utils(FIFO_main_sequence)
  int unsigned num_random = 3000;
  function new(string name = "FIFO_main_sequence"); super.new(name); endfunction
  task body();
    FIFO_reset_sequence       rst  = FIFO_reset_sequence      ::type_id::create("rst");
    FIFO_write_only_sequence  wo    = FIFO_write_only_sequence ::type_id::create("wo");
    FIFO_read_only_sequence   ro    = FIFO_read_only_sequence  ::type_id::create("ro");
    FIFO_write_read_sequence  wr_rd = FIFO_write_read_sequence ::type_id::create("wr_rd");
    FIFO_flags_sequence       flg   = FIFO_flags_sequence      ::type_id::create("flg");
    FIFO_wrap_sequence        wrp   = FIFO_wrap_sequence       ::type_id::create("wrp");
    FIFO_reset_mid_sequence   rstm  = FIFO_reset_mid_sequence  ::type_id::create("rstm");
    FIFO_random_sequence      rnd   = FIFO_random_sequence     ::type_id::create("rnd");
    rnd.num = num_random;

    rst.start(m_sequencer, this);  wo.start(m_sequencer, this);   ro.start(m_sequencer, this);
    rst.start(m_sequencer, this);  wr_rd.start(m_sequencer, this);
    rst.start(m_sequencer, this);  flg.start(m_sequencer, this);
    rst.start(m_sequencer, this);  wrp.start(m_sequencer, this);
    rst.start(m_sequencer, this);  rstm.start(m_sequencer, this);
    rst.start(m_sequencer, this);  rnd.start(m_sequencer, this);
  endtask
endclass

endpackage
