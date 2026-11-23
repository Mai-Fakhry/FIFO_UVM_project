package FIFO_scoreboard_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;
  import FIFO_seq_item_pkg::*;

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

endpackage
