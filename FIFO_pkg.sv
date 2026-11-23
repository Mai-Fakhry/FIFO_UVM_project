package FIFO_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;

// ============================================================================
// FIFO_seq_item
// ============================================================================
////////////////////////////////////////////////////////////////////////////////
// FIFO_seq_item : one clock cycle of FIFO activity.
//   * stimulus fields  (rand)  : rst_n, wr_en, rd_en, data_in
//   * observation fields       : filled by the MONITOR for every sampled cycle
//   * knobs (non-rand)         : weights used by the constraints; sequences tune
//                                them to bias the randomisation
////////////////////////////////////////////////////////////////////////////////
class FIFO_seq_item extends uvm_sequence_item;
  `uvm_object_utils(FIFO_seq_item)

  // ------------------------------------------------------------ stimulus
  rand logic                   rst_n;
  rand logic                   wr_en;
  rand logic                   rd_en;
  rand logic [FIFO_WIDTH-1:0]  data_in;

  // ------------------------------------------------------- observations
  logic [FIFO_WIDTH-1:0] data_out;
  logic                  wr_ack, overflow;
  logic                  full, empty, almostfull, almostempty, underflow;

  // -------------------------------------------------------------- knobs
  // (percentages, 0..100). Defaults reproduce the SV project: 70 % writes / 30 % reads.
  int unsigned RST_N_ON_DIST = 98;   // 98 % of random cycles have rst_n = 1
  int unsigned WR_EN_ON_DIST = 70;
  int unsigned RD_EN_ON_DIST = 30;
  int unsigned DATA_CORNER_PCT = 20; // % of cycles that use a corner data value

  // ------------------------------------------------------- constraints
  // 1. reset is rare so that the FIFO can actually reach full / empty-after-fill
  constraint c_rst_dist {
    rst_n dist { 1'b1 := RST_N_ON_DIST, 1'b0 := (100 - RST_N_ON_DIST) };
  }

  // 2. independent enable distributions (same idea as the SV project)
  constraint c_wr_en_dist {
    wr_en dist { 1'b1 := WR_EN_ON_DIST, 1'b0 := (100 - WR_EN_ON_DIST) };
  }
  constraint c_rd_en_dist {
    rd_en dist { 1'b1 := RD_EN_ON_DIST, 1'b0 := (100 - RD_EN_ON_DIST) };
  }

  // 3. data: hit width corner values (all-0, all-1, checkerboards, walking-1 ends)
  //    often enough to be covered, otherwise uniformly random.
  constraint c_data_dist {
    data_in dist {
      {FIFO_WIDTH{1'b0}} := DATA_CORNER_PCT,
      {FIFO_WIDTH{1'b1}} := DATA_CORNER_PCT,
      {(FIFO_WIDTH/2){2'b10}} := DATA_CORNER_PCT/2,
      {(FIFO_WIDTH/2){2'b01}} := DATA_CORNER_PCT/2,
      [1 : {FIFO_WIDTH{1'b1}}-1] :/ (100 - 3*DATA_CORNER_PCT)
    };
  }

  // 4. OPTIONAL constraint blocks. They are OFF by default (constraint_mode(0) in new())
  //    and are switched on by the directed sequences, e.g. write_only_seq enables
  //    c_write_only and the item can then never read.
  constraint c_write_only  { rst_n == 1; wr_en == 1; rd_en == 0; }
  constraint c_read_only   { rst_n == 1; wr_en == 0; rd_en == 1; }
  constraint c_write_read  { rst_n == 1; wr_en == 1; rd_en == 1; }
  constraint c_idle        { rst_n == 1; wr_en == 0; rd_en == 0; }
  constraint c_in_reset    { rst_n == 0; wr_en == 0; rd_en == 0; }
  // reset glitch with traffic on the bus: reset has priority, traffic must be ignored
  constraint c_reset_traffic { rst_n == 0; wr_en dist {1:=50, 0:=50}; rd_en dist {1:=50, 0:=50}; }

  function new(string name = "FIFO_seq_item");
    super.new(name);
    c_write_only.constraint_mode(0);
    c_read_only.constraint_mode(0);
    c_write_read.constraint_mode(0);
    c_idle.constraint_mode(0);
    c_in_reset.constraint_mode(0);
    c_reset_traffic.constraint_mode(0);
  endfunction

  // helper used by sequences: turn exactly one directed constraint on
  function void set_mode(string m);
    c_write_only.constraint_mode(0);  c_read_only.constraint_mode(0);
    c_write_read.constraint_mode(0);  c_idle.constraint_mode(0);
    c_in_reset.constraint_mode(0);    c_reset_traffic.constraint_mode(0);
    case (m)
      "write_only"    : c_write_only.constraint_mode(1);
      "read_only"     : c_read_only.constraint_mode(1);
      "write_read"    : c_write_read.constraint_mode(1);
      "idle"          : c_idle.constraint_mode(1);
      "in_reset"      : c_in_reset.constraint_mode(1);
      "reset_traffic" : c_reset_traffic.constraint_mode(1);
      "random", ""    : ;                       // keep only the dist constraints
      default         : `uvm_error("ITEM", $sformatf("unknown mode '%s'", m))
    endcase
  endfunction

  // --------------------------------------------------- UVM data methods
  function void do_copy(uvm_object rhs);
    FIFO_seq_item t;
    super.do_copy(rhs);
    if (!$cast(t, rhs)) `uvm_fatal("ITEM", "do_copy: cast failed")
    rst_n = t.rst_n;   wr_en = t.wr_en;   rd_en = t.rd_en;   data_in = t.data_in;
    data_out = t.data_out; wr_ack = t.wr_ack; overflow = t.overflow;
    full = t.full; empty = t.empty; almostfull = t.almostfull;
    almostempty = t.almostempty; underflow = t.underflow;
  endfunction

  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    FIFO_seq_item t;
    if (!$cast(t, rhs)) return 0;
    return super.do_compare(rhs, comparer) &&
           rst_n === t.rst_n && wr_en === t.wr_en && rd_en === t.rd_en &&
           data_in === t.data_in && data_out === t.data_out &&
           wr_ack === t.wr_ack && overflow === t.overflow && full === t.full &&
           empty === t.empty && almostfull === t.almostfull &&
           almostempty === t.almostempty && underflow === t.underflow;
  endfunction

  function string convert2string();
    return $sformatf("rst_n=%0b wr_en=%0b rd_en=%0b din=%04h | dout=%04h ack=%0b ovf=%0b udf=%0b F=%0b E=%0b AF=%0b AE=%0b",
                     rst_n, wr_en, rd_en, data_in, data_out, wr_ack, overflow, underflow,
                     full, empty, almostfull, almostempty);
  endfunction
endclass

// ============================================================================
// FIFO_config
// ============================================================================
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

// ============================================================================
// FIFO_sequencer
// ============================================================================
typedef uvm_sequencer #(FIFO_seq_item) FIFO_sequencer;

// ============================================================================
// FIFO_sequences
// ============================================================================
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

// ============================================================================
// FIFO_driver
// ============================================================================
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

// ============================================================================
// FIFO_monitor
// ============================================================================
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

// ============================================================================
// FIFO_agent
// ============================================================================
class FIFO_agent extends uvm_agent;
  `uvm_component_utils(FIFO_agent)

  FIFO_sequencer sqr;
  FIFO_driver    drv;
  FIFO_monitor   mon;
  FIFO_config    cfg;
  uvm_analysis_port #(FIFO_seq_item) ap;   // re-exported monitor port

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(FIFO_config)::get(this, "", "FIFO_cfg", cfg))
      `uvm_fatal("AGT", "FIFO_config not found in config_db")
    mon = FIFO_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = FIFO_sequencer::type_id::create("sqr", this);
      drv = FIFO_driver   ::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    ap = mon.ap;
    if (cfg.is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

// ============================================================================
// FIFO_scoreboard
// ============================================================================
////////////////////////////////////////////////////////////////////////////////
// FIFO_scoreboard : self-checking reference model + comparator.
//
// It receives ONE transaction per clock cycle from the monitor (the values seen at
// the rising edge) and keeps a queue-based golden model of the FIFO.
//
// What is compared in a cycle N (t = sampled values at edge N):
//   - FLAGS (combinational in the DUT -> reflect the state BEFORE edge N):
//        full / empty / almostfull / almostempty / underflow
//   - REGISTERED outputs (they answer the operation done at edge N-1):
//        data_out, wr_ack, overflow
//   Then the model advances with the inputs of cycle N, producing the
//   expectations used at cycle N+1.
//
// Async reset: the driver asserts rst_n on the falling edge, so by the next rising
// edge the DUT is already cleared -> the model is cleared BEFORE the compare when
// the sampled rst_n is 0.
////////////////////////////////////////////////////////////////////////////////
class FIFO_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(FIFO_scoreboard)

  uvm_analysis_imp #(FIFO_seq_item, FIFO_scoreboard) imp;

  // golden model state
  logic [FIFO_WIDTH-1:0] ref_q [$];
  logic [FIFO_WIDTH-1:0] exp_dout;
  bit                    exp_ack, exp_ovf;

  // statistics
  int unsigned cycles, correct_count, error_count;
  int unsigned n_writes, n_reads, n_ovf, n_udf, n_resets, max_level;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_dout = '0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction

  // compare helper -----------------------------------------------------------
  local function void chk(string what, logic [FIFO_WIDTH-1:0] got, logic [FIFO_WIDTH-1:0] exp,
                          FIFO_seq_item t, ref bit ok);
    if (got !== exp) begin
      ok = 0;
      `uvm_error("SCB", $sformatf("%s mismatch: DUT=%0h EXPECTED=%0h  [%s] model_level=%0d",
                 what, got, exp, t.convert2string(), ref_q.size()))
    end
  endfunction

  function void write(FIFO_seq_item t);
    bit ok = 1;
    bit e_full, e_empty, e_af, e_ae, e_uf;
    bit wr_ok, rd_ok;
    cycles++;

    // ---- asynchronous reset already took effect inside the DUT
    if (!t.rst_n) begin
      ref_q.delete();
      exp_dout = '0;  exp_ack = 0;  exp_ovf = 0;
      n_resets++;
    end

    // ---- expected combinational flags from the model state
    e_full  = (ref_q.size() == FIFO_DEPTH);
    e_empty = (ref_q.size() == 0);
    e_af    = (ref_q.size() == FIFO_DEPTH-1);
    e_ae    = (ref_q.size() == 1);
    e_uf    = e_empty && t.rd_en;

    // ---- compare
    chk("data_out",    t.data_out,    exp_dout, t, ok);
    chk("wr_ack",      t.wr_ack,      exp_ack,  t, ok);
    chk("overflow",    t.overflow,    exp_ovf,  t, ok);
    chk("full",        t.full,        e_full,   t, ok);
    chk("empty",       t.empty,       e_empty,  t, ok);
    chk("almostfull",  t.almostfull,  e_af,     t, ok);
    chk("almostempty", t.almostempty, e_ae,     t, ok);
    chk("underflow",   t.underflow,   e_uf,     t, ok);

    if (ok) correct_count++; else error_count++;

    // ---- advance the model with this cycle's inputs (next cycle's expectations)
    if (t.rst_n) begin
      wr_ok   = t.wr_en && (ref_q.size() <  FIFO_DEPTH);
      rd_ok   = t.rd_en && (ref_q.size() != 0);
      exp_ack = wr_ok;
      exp_ovf = t.wr_en && e_full;          // write attempted on a full FIFO
      if (e_uf)  n_udf++;
      if (exp_ovf) n_ovf++;
      if (rd_ok) begin
        exp_dout = ref_q.pop_front();       // read sees the oldest entry
        n_reads++;
      end
      if (wr_ok) begin
        ref_q.push_back(t.data_in);
        n_writes++;
      end
      if (ref_q.size() > max_level) max_level = ref_q.size();
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf(
      "\n  ---------------- SCOREBOARD SUMMARY ----------------\n  cycles checked : %0d\n  correct cycles : %0d\n  error  cycles  : %0d\n  legal writes=%0d legal reads=%0d overflows=%0d underflows=%0d resets=%0d max_level=%0d\n  ----------------------------------------------------",
      cycles, correct_count, error_count, n_writes, n_reads, n_ovf, n_udf, n_resets, max_level), UVM_LOW)
  endfunction
endclass

// ============================================================================
// FIFO_coverage
// ============================================================================
////////////////////////////////////////////////////////////////////////////////
// FIFO_coverage : functional coverage collector (uvm_subscriber on the monitor).
//
// Covergroups
//   cg_flags : every I/O signal (active / not active) + the crosses of the SV project
//              (cr1..cr7, now with correct previous-cycle semantics for the registered
//              outputs wr_ack / overflow and with illegal_bins for impossible combos)
//   cg_state : FIFO state (empty / almost-empty / mid / almost-full / full) x operation
//   cg_trans : state transitions (fill / drain chains), op-to-op transitions,
//              full / empty rise & fall
//   cg_data  : data patterns written and read back
//   cg_reset : reset behaviour (reset hitting every FIFO state, traffic while in reset)
////////////////////////////////////////////////////////////////////////////////
class FIFO_coverage extends uvm_subscriber #(FIFO_seq_item);
  `uvm_component_utils(FIFO_coverage)

  // FIFO occupancy class derived from the four flags
  typedef bit [2:0] state_e;
  localparam state_e ST_EMPTY = 0, ST_ALMOSTEMPTY = 1, ST_MID = 2,
                     ST_ALMOSTFULL = 3, ST_FULL = 4, ST_ILLEGAL = 5;

  // ---- sampled copies of the current cycle
  bit                    cv_rst_n, cv_wr_en, cv_rd_en;
  bit [FIFO_WIDTH-1:0]   cv_din, cv_dout;
  bit                    cv_ack, cv_ovf, cv_full, cv_empty, cv_af, cv_ae, cv_udf;
  state_e                cv_state;
  bit [1:0]              cv_op;        // {wr_en, rd_en}
  // ---- previous cycle (needed for registered outputs & transitions)
  bit                    pv_valid, pv_rst_n, pv_wr_en, pv_rd_en, pv_full, pv_empty;
  state_e                pv_state;

  localparam bit [FIFO_WIDTH-1:0] ALL1  = {FIFO_WIDTH{1'b1}};
  localparam bit [FIFO_WIDTH-1:0] CHK_A = {(FIFO_WIDTH/2){2'b10}};
  localparam bit [FIFO_WIDTH-1:0] CHK_B = {(FIFO_WIDTH/2){2'b01}};

  // ===========================================================================
  covergroup cg_flags;
    option.per_instance = 1;
    option.name = "cg_flags";

    cp_wr_en:  coverpoint cv_wr_en  iff (cv_rst_n) { bins wr_en_active = {1}; bins wr_en_not_active = {0}; }
    cp_rd_en:  coverpoint cv_rd_en  iff (cv_rst_n) { bins rd_en_active = {1}; bins rd_en_not_active = {0}; }
    cp_wr_ack: coverpoint cv_ack    iff (cv_rst_n) { bins wr_ack_active = {1}; bins wr_ack_not_active = {0}; }
    cp_overflow: coverpoint cv_ovf  iff (cv_rst_n) { bins overflow_active = {1}; bins overflow_not_active = {0}; }
    cp_full:   coverpoint cv_full   iff (cv_rst_n) { bins full_active = {1}; bins full_not_active = {0}; }
    cp_empty:  coverpoint cv_empty  iff (cv_rst_n) { bins empty_active = {1}; bins empty_not_active = {0}; }
    cp_almostfull:  coverpoint cv_af iff (cv_rst_n) { bins almostfull_active = {1}; bins almostfull_not_active = {0}; }
    cp_almostempty: coverpoint cv_ae iff (cv_rst_n) { bins almostempty_active = {1}; bins almostempty_not_active = {0}; }
    cp_underflow:   coverpoint cv_udf iff (cv_rst_n) { bins underflow_active = {1}; bins underflow_not_active = {0}; }

    // previous-cycle helpers for the registered outputs
    cp_p_wr_en: coverpoint pv_wr_en iff (cv_rst_n && pv_valid && pv_rst_n) { bins p_wr_on = {1}; bins p_wr_off = {0}; }
    cp_p_full:  coverpoint pv_full  iff (cv_rst_n && pv_valid && pv_rst_n) { bins p_full_on = {1}; bins p_full_off = {0}; }

    // ---- crosses carried over from the SV project (operation x flag)
    cr1: cross cp_wr_en, cp_rd_en, cp_full;
    cr2: cross cp_wr_en, cp_rd_en, cp_empty;
    cr3: cross cp_wr_en, cp_rd_en, cp_almostfull;
    cr4: cross cp_wr_en, cp_rd_en, cp_almostempty;
    cr5: cross cp_wr_en, cp_rd_en, cp_underflow {
      // underflow = empty & rd_en  -> can never be 1 when rd_en = 0
      illegal_bins rd_off_underflow_on =
        binsof(cp_rd_en) intersect {0} && binsof(cp_underflow) intersect {1};
    }
    // ---- registered outputs crossed with what happened on the PREVIOUS cycle
    // overflow(t) must equal  wr_en(t-1) & full(t-1)
    cr6_ovf: cross cp_p_wr_en, cp_p_full, cp_overflow {
      illegal_bins ovf_without_write   = binsof(cp_overflow) intersect {1} && binsof(cp_p_wr_en) intersect {0};
      illegal_bins ovf_when_not_full   = binsof(cp_overflow) intersect {1} && binsof(cp_p_full)  intersect {0};
      illegal_bins missing_ovf         = binsof(cp_overflow) intersect {0} && binsof(cp_p_wr_en) intersect {1}
                                                                           && binsof(cp_p_full)  intersect {1};
    }
    // wr_ack(t) must equal  wr_en(t-1) & !full(t-1)
    cr7_ack: cross cp_p_wr_en, cp_p_full, cp_wr_ack {
      illegal_bins ack_without_write   = binsof(cp_wr_ack) intersect {1} && binsof(cp_p_wr_en) intersect {0};
      illegal_bins ack_when_full       = binsof(cp_wr_ack) intersect {1} && binsof(cp_p_full)  intersect {1};
      illegal_bins missing_ack         = binsof(cp_wr_ack) intersect {0} && binsof(cp_p_wr_en) intersect {1}
                                                                          && binsof(cp_p_full)  intersect {0};
    }
    // ---- flag mutual-exclusion (illegal combos)
    cp_flag_vec: coverpoint {cv_full, cv_empty, cv_af, cv_ae} iff (cv_rst_n) {
      bins f_empty       = {4'b0100};
      bins f_almostempty = {4'b0001};
      bins f_mid         = {4'b0000};
      bins f_almostfull  = {4'b0010};
      bins f_full        = {4'b1000};
      illegal_bins f_illegal = default;
    }
  endgroup

  // ===========================================================================
  covergroup cg_state;
    option.per_instance = 1;
    option.name = "cg_state";
    cp_state: coverpoint cv_state iff (cv_rst_n) {
      bins empty = {ST_EMPTY}; bins almostempty = {ST_ALMOSTEMPTY}; bins mid = {ST_MID};
      bins almostfull = {ST_ALMOSTFULL}; bins full = {ST_FULL};
      illegal_bins illegal = {ST_ILLEGAL};
    }
    cp_op: coverpoint cv_op iff (cv_rst_n) {
      bins idle = {2'b00}; bins read_only = {2'b01}; bins write_only = {2'b10}; bins write_read = {2'b11};
    }
    // every operation in every FIFO state: 5 x 4 = 20 bins
    state_x_op: cross cp_state, cp_op;
  endgroup

  // ===========================================================================
  covergroup cg_trans;
    option.per_instance = 1;
    option.name = "cg_trans";
    cp_state_tr: coverpoint cv_state iff (cv_rst_n && pv_rst_n) {
      bins fill_step[]  = (ST_EMPTY => ST_ALMOSTEMPTY), (ST_ALMOSTEMPTY => ST_MID),
                          (ST_MID => ST_ALMOSTFULL),    (ST_ALMOSTFULL => ST_FULL);
      bins drain_step[] = (ST_FULL => ST_ALMOSTFULL),   (ST_ALMOSTFULL => ST_MID),
                          (ST_MID => ST_ALMOSTEMPTY),   (ST_ALMOSTEMPTY => ST_EMPTY);
      bins fill_chain  = (ST_EMPTY => ST_ALMOSTEMPTY => ST_MID[*1:8] => ST_ALMOSTFULL => ST_FULL);
      bins drain_chain = (ST_FULL => ST_ALMOSTFULL => ST_MID[*1:8] => ST_ALMOSTEMPTY => ST_EMPTY);
      bins hold_almostfull = (ST_ALMOSTFULL[*2:4]);   // sitting at almost-full (e.g. wr+rd or idle)
      bins hold_almostempty = (ST_ALMOSTEMPTY[*2:4]);
    }
    cp_op_tr: coverpoint cv_op iff (cv_rst_n && pv_rst_n) {
      bins op_tr[] = ([0:3] => [0:3]);                         // 16 op-to-op transitions
    }
    cp_full_tr:  coverpoint cv_full  iff (cv_rst_n && pv_rst_n) { bins rise = (0 => 1); bins fall = (1 => 0); bins hold_full = (1[*2:4]); }
    cp_empty_tr: coverpoint cv_empty iff (cv_rst_n && pv_rst_n) { bins rise = (0 => 1); bins fall = (1 => 0); bins hold_empty = (1[*2:4]); }
    cp_ovf_tr:   coverpoint cv_ovf   iff (cv_rst_n && pv_rst_n) { bins ovf_pulse = (0 => 1 => 0); bins ovf_back2back = (1[*2:8]); }
    cp_udf_tr:   coverpoint cv_udf   iff (cv_rst_n && pv_rst_n) { bins udf_pulse = (0 => 1 => 0); bins udf_back2back = (1[*2:8]); }
  endgroup

  // ===========================================================================
  covergroup cg_data;
    option.per_instance = 1;
    option.name = "cg_data";
    cp_din_written: coverpoint cv_din iff (cv_rst_n && cv_wr_en && !cv_full) {
      bins zero = {0}; bins ones = {ALL1}; bins checker_a = {CHK_A}; bins checker_b = {CHK_B};
      bins low  = {[1:16'h3FFF]}; bins mid_lo = {[16'h4000:16'h7FFF]};
      bins mid_hi = {[16'h8000:16'hBFFF]}; bins high = {[16'hC000:ALL1-1]};
    }
    cp_dout_read: coverpoint cv_dout iff (cv_rst_n && pv_valid && pv_rst_n && pv_rd_en && !pv_empty) {
      bins zero = {0}; bins ones = {ALL1}; bins checker_a = {CHK_A}; bins checker_b = {CHK_B};
      bins low  = {[1:16'h3FFF]}; bins mid_lo = {[16'h4000:16'h7FFF]};
      bins mid_hi = {[16'h8000:16'hBFFF]}; bins high = {[16'hC000:ALL1-1]};
    }
  endgroup

  // ===========================================================================
  covergroup cg_reset;
    option.per_instance = 1;
    option.name = "cg_reset";
    cp_rst_n: coverpoint cv_rst_n { bins asserted = {0}; bins deasserted = {1};
                                    bins fall = (1 => 0); bins rise = (0 => 1); bins held_2cyc = (0[*2]); }
    // state of the FIFO just before reset was applied
    cp_rst_when: coverpoint pv_state iff (pv_valid && pv_rst_n && !cv_rst_n) {
      bins r_empty = {ST_EMPTY}; bins r_almostempty = {ST_ALMOSTEMPTY}; bins r_mid = {ST_MID};
      bins r_almostfull = {ST_ALMOSTFULL}; bins r_full = {ST_FULL};
    }
    // wr/rd activity while reset is low (reset must win)
    cp_rst_traffic: coverpoint cv_op iff (!cv_rst_n) {
      bins r_idle = {2'b00}; bins r_rd = {2'b01}; bins r_wr = {2'b10}; bins r_wr_rd = {2'b11};
    }
  endgroup


  // ===========================================================================
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_flags = new();  cg_state = new();  cg_trans = new();  cg_data = new();  cg_reset = new();
  endfunction

  function state_e decode_state(bit f, bit e, bit af, bit ae);
    case ({f, e, af, ae})
      4'b0100: return ST_EMPTY;
      4'b0001: return ST_ALMOSTEMPTY;
      4'b0000: return ST_MID;
      4'b0010: return ST_ALMOSTFULL;
      4'b1000: return ST_FULL;
      default: return ST_ILLEGAL;
    endcase
  endfunction

  // uvm_subscriber hook: called by the monitor's analysis port every cycle
  function void write(FIFO_seq_item t);
    cv_rst_n = t.rst_n;      cv_wr_en = t.wr_en;     cv_rd_en = t.rd_en;
    cv_din   = t.data_in;    cv_dout  = t.data_out;
    cv_ack   = t.wr_ack;     cv_ovf   = t.overflow;
    cv_full  = t.full;       cv_empty = t.empty;
    cv_af    = t.almostfull; cv_ae    = t.almostempty;  cv_udf = t.underflow;
    cv_op    = {t.wr_en, t.rd_en};
    cv_state = decode_state(t.full, t.empty, t.almostfull, t.almostempty);

    cg_flags.sample();
    cg_state.sample();
    cg_trans.sample();
    cg_data.sample();
    cg_reset.sample();

    pv_valid = 1;  pv_rst_n = cv_rst_n; pv_wr_en = cv_wr_en; pv_rd_en = cv_rd_en;
    pv_full  = cv_full; pv_empty = cv_empty; pv_state = cv_state;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("functional coverage: flags=%.1f%% state=%.1f%% trans=%.1f%% data=%.1f%% reset=%.1f%%",
              cg_flags.get_inst_coverage(), cg_state.get_inst_coverage(), cg_trans.get_inst_coverage(),
              cg_data.get_inst_coverage(),  cg_reset.get_inst_coverage()), UVM_LOW)
  endfunction
endclass

// ============================================================================
// FIFO_env
// ============================================================================
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

// ============================================================================
// FIFO_tests
// ============================================================================
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
