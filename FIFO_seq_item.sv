package FIFO_seq_item_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;

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

endpackage
