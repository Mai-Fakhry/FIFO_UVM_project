////////////////////////////////////////////////////////////////////////////////
// FIFO_SVA : assertion + cover module, attached to the DUT with `bind`
//            (see FIFO_TOP.sv).  Because it is bound *inside* FIFO it can also
//            observe the internal count / wr_ptr / rd_ptr.
//
//   a_*  : assert property   (checks)
//   c_*  : cover  property   (scenario coverage  -> "sequential domain" coverage)
//
// Cycle semantics of the DUT (needed to read the properties):
//   - wr_ack / overflow / data_out are REGISTERED  -> they answer the PREVIOUS cycle
//   - full / empty / almostfull / almostempty / underflow are COMBINATIONAL
//   - count / wr_ptr / rd_ptr update on the clock edge (visible next cycle)
////////////////////////////////////////////////////////////////////////////////
module FIFO_SVA #(parameter int W = 16, parameter int D = 8) (
  input logic              clk, rst_n, wr_en, rd_en,
  input logic [W-1:0]      data_in, data_out,
  input logic              wr_ack, overflow, full, empty, almostfull, almostempty, underflow,
  // internal DUT state (bound from inside the FIFO module)
  input logic [$clog2(D):0]   count,
  input logic [$clog2(D)-1:0] wr_ptr, rd_ptr
);

  // ---------------------------------------------------------------------------
  // 1. RESET
  // ---------------------------------------------------------------------------
  // Sampled view: while reset is low every state element is cleared.
  a_reset_values: assert property (@(posedge clk)
      !rst_n |-> (count == 0 && wr_ptr == 0 && rd_ptr == 0 &&
                  data_out == '0 && !wr_ack && !overflow))
    else $error("[SVA] a_reset_values: state not cleared while rst_n=0");

  // Asynchronous view: the clear must happen *without waiting for a clock edge*.
  // Checked 1 time-unit after the falling edge of rst_n (the clock edge is 5 units
  // away because the driver releases/asserts reset on the falling clock edge).
  always @(negedge rst_n) begin
    #1;
    a_async_reset: assert (count == 0 && wr_ptr == 0 && rd_ptr == 0 &&
                           data_out == '0 && !wr_ack && !overflow)
      else $error("[SVA] a_async_reset: reset did not act asynchronously");
    c_async_reset: cover (1'b1);
  end

  // reset applied while the FIFO holds data / is full / while writing
  c_reset_when_nonempty: cover property (@(posedge clk) (rst_n && count != 0) ##1 !rst_n);
  c_reset_when_full:     cover property (@(posedge clk) (rst_n && full)       ##1 !rst_n);
  c_reset_during_write:  cover property (@(posedge clk) (rst_n && wr_en)      ##1 !rst_n);
  c_reset_release:       cover property (@(posedge clk) !rst_n ##1 rst_n);

  // ---------------------------------------------------------------------------
  // 2. FLAG CORRECTNESS (all derived from count)
  // ---------------------------------------------------------------------------
  a_full:        assert property (@(posedge clk) disable iff (!rst_n)
                   full == (count == D))
    else $error("[SVA] a_full: full=%0b count=%0d", full, count);

  a_empty:       assert property (@(posedge clk) disable iff (!rst_n)
                   empty == (count == 0))
    else $error("[SVA] a_empty: empty=%0b count=%0d", empty, count);

  a_almostfull:  assert property (@(posedge clk) disable iff (!rst_n)
                   almostfull == (count == D-1))
    else $error("[SVA] a_almostfull: almostfull=%0b count=%0d", almostfull, count);

  a_almostempty: assert property (@(posedge clk) disable iff (!rst_n)
                   almostempty == (count == 1))
    else $error("[SVA] a_almostempty: almostempty=%0b count=%0d", almostempty, count);

  a_underflow:   assert property (@(posedge clk) disable iff (!rst_n)
                   underflow == (empty && rd_en))
    else $error("[SVA] a_underflow: underflow=%0b empty=%0b rd_en=%0b", underflow, empty, rd_en);

  a_flags_excl:  assert property (@(posedge clk) disable iff (!rst_n)
                   !(full && empty) && !(almostfull && (full || empty)) &&
                   !(almostempty && (full || empty)) && !(almostfull && almostempty))
    else $error("[SVA] a_flags_excl: illegal flag combination {F,E,AF,AE}={%0b%0b%0b%0b}",
                full, empty, almostfull, almostempty);

  a_outputs_known: assert property (@(posedge clk)
                   !$isunknown({data_out, wr_ack, overflow, full, empty,
                                almostfull, almostempty, underflow}))
    else $error("[SVA] a_outputs_known: X/Z on a DUT output");

  c_full:        cover property (@(posedge clk) disable iff (!rst_n) $rose(full));
  c_empty:       cover property (@(posedge clk) disable iff (!rst_n) $rose(empty));
  c_almostfull:  cover property (@(posedge clk) disable iff (!rst_n) $rose(almostfull));
  c_almostempty: cover property (@(posedge clk) disable iff (!rst_n) $rose(almostempty));
  c_underflow:   cover property (@(posedge clk) disable iff (!rst_n) underflow);

  // ---------------------------------------------------------------------------
  // 3. WRITE PATH  (wr_ack / overflow)
  // ---------------------------------------------------------------------------
  a_wr_ack_fwd:  assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && !full) |=> wr_ack)
    else $error("[SVA] a_wr_ack_fwd: legal write was not acknowledged");

  a_wr_ack_rev:  assert property (@(posedge clk) disable iff (!rst_n)
                   wr_ack |-> ($past(wr_en) && !$past(full)))
    else $error("[SVA] a_wr_ack_rev: wr_ack without a legal write in previous cycle");

  a_no_ack_full: assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && full) |=> !wr_ack)
    else $error("[SVA] a_no_ack_full: write accepted while FIFO was full");

  a_ovf_fwd:     assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && full) |=> overflow)
    else $error("[SVA] a_ovf_fwd: overflow not flagged after write while full");

  a_ovf_rev:     assert property (@(posedge clk) disable iff (!rst_n)
                   overflow |-> ($past(full) && $past(wr_en)))
    else $error("[SVA] a_ovf_rev: overflow without (full & wr_en) in previous cycle");

  a_ack_ovf_excl: assert property (@(posedge clk) disable iff (!rst_n)
                   !(wr_ack && overflow))
    else $error("[SVA] a_ack_ovf_excl: wr_ack and overflow asserted together");

  c_wr_ack:      cover property (@(posedge clk) disable iff (!rst_n) (wr_en && !full) ##1 wr_ack);
  c_overflow:    cover property (@(posedge clk) disable iff (!rst_n) (wr_en && full)  ##1 overflow);
  c_ovf_back2back: cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && full) ##1 (wr_en && full) ##1 overflow);
  c_ovf_with_rd: cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && full) ##1 overflow);   // write rejected even though a read frees a slot

  // ---------------------------------------------------------------------------
  // 4. OCCUPANCY COUNTER
  // ---------------------------------------------------------------------------
  a_count_range: assert property (@(posedge clk) disable iff (!rst_n) count <= D)
    else $error("[SVA] a_count_range: count=%0d > FIFO_DEPTH", count);

  a_cnt_inc:     assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && !rd_en && !full) |=> (count == $past(count) + 1))
    else $error("[SVA] a_cnt_inc: count did not increment on write");

  a_cnt_dec:     assert property (@(posedge clk) disable iff (!rst_n)
                   (rd_en && !wr_en && !empty) |=> (count == $past(count) - 1))
    else $error("[SVA] a_cnt_dec: count did not decrement on read");

  a_cnt_hold:    assert property (@(posedge clk) disable iff (!rst_n)
                   (!wr_en && !rd_en) |=> $stable(count))
    else $error("[SVA] a_cnt_hold: count moved while idle");

  a_cnt_sat_full: assert property (@(posedge clk) disable iff (!rst_n)
                   (full && wr_en && !rd_en) |=> (count == D))
    else $error("[SVA] a_cnt_sat_full: count moved on write-while-full");

  a_cnt_sat_empty: assert property (@(posedge clk) disable iff (!rst_n)
                   (empty && rd_en && !wr_en) |=> (count == 0))
    else $error("[SVA] a_cnt_sat_empty: count moved on read-while-empty");

  // simultaneous read + write, three different FIFO states
  a_rw_mid:      assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && !full && !empty) |=> $stable(count))
    else $error("[SVA] a_rw_mid: count must hold on simultaneous wr+rd (mid-level)");

  a_rw_empty:    assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && empty) |=> (count == $past(count) + 1))
    else $error("[SVA] a_rw_empty: simultaneous wr+rd on empty FIFO must only write");

  a_rw_full:     assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && full) |=> (count == $past(count) - 1))
    else $error("[SVA] a_rw_full: simultaneous wr+rd on full FIFO must only read");

  c_rw_mid:      cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && !full && !empty) ##1 1'b1);
  c_rw_empty:    cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && empty) ##1 (count == 1));
  c_rw_full:     cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && rd_en && full)  ##1 (count == D-1));
  c_fill_to_full: cover property (@(posedge clk) disable iff (!rst_n)
                   $fell(empty) ##[1:$] full);          // filled from empty all the way up
  c_drain_to_empty: cover property (@(posedge clk) disable iff (!rst_n)
                   full ##[1:$] empty);                       // full -> completely drained

  // ---------------------------------------------------------------------------
  // 5. POINTERS
  // ---------------------------------------------------------------------------
  a_wr_ptr_range: assert property (@(posedge clk) disable iff (!rst_n) wr_ptr < D)
    else $error("[SVA] a_wr_ptr_range: wr_ptr=%0d", wr_ptr);
  a_rd_ptr_range: assert property (@(posedge clk) disable iff (!rst_n) rd_ptr < D)
    else $error("[SVA] a_rd_ptr_range: rd_ptr=%0d", rd_ptr);

  a_wr_ptr_inc:  assert property (@(posedge clk) disable iff (!rst_n)
                   (wr_en && !full) |=> (int'(wr_ptr) == ((int'($past(wr_ptr)) + 1) % D)))
    else $error("[SVA] a_wr_ptr_inc: wr_ptr did not advance (mod D) on legal write");
  a_wr_ptr_hold: assert property (@(posedge clk) disable iff (!rst_n)
                   !(wr_en && !full) |=> $stable(wr_ptr))
    else $error("[SVA] a_wr_ptr_hold: wr_ptr moved without a legal write");

  a_rd_ptr_inc:  assert property (@(posedge clk) disable iff (!rst_n)
                   (rd_en && !empty) |=> (int'(rd_ptr) == ((int'($past(rd_ptr)) + 1) % D)))
    else $error("[SVA] a_rd_ptr_inc: rd_ptr did not advance (mod D) on legal read");
  a_rd_ptr_hold: assert property (@(posedge clk) disable iff (!rst_n)
                   !(rd_en && !empty) |=> $stable(rd_ptr))
    else $error("[SVA] a_rd_ptr_hold: rd_ptr moved without a legal read");

  // pointer distance must always equal the occupancy (mod D)
  a_ptr_vs_count: assert property (@(posedge clk) disable iff (!rst_n)
                   ((int'(wr_ptr) - int'(rd_ptr) + D) % D) == (int'(count) % D))
    else $error("[SVA] a_ptr_vs_count: wr_ptr=%0d rd_ptr=%0d count=%0d", wr_ptr, rd_ptr, count);

  c_wr_ptr_wrap: cover property (@(posedge clk) disable iff (!rst_n)
                   (wr_ptr == D-1 && wr_en && !full) ##1 (wr_ptr == 0));
  c_rd_ptr_wrap: cover property (@(posedge clk) disable iff (!rst_n)
                   (rd_ptr == D-1 && rd_en && !empty) ##1 (rd_ptr == 0));

  // ---------------------------------------------------------------------------
  // 6. READ PATH (data_out)
  // ---------------------------------------------------------------------------
  a_dout_stable: assert property (@(posedge clk) disable iff (!rst_n)
                   !(rd_en && !empty) |=> $stable(data_out))
    else $error("[SVA] a_dout_stable: data_out changed without a legal read");

  a_underflow_noside: assert property (@(posedge clk) disable iff (!rst_n)
                   (empty && rd_en) |=> ($stable(rd_ptr) && $stable(data_out)))
    else $error("[SVA] a_underflow_noside: read on empty FIFO had a side effect");

  c_rd_valid:    cover property (@(posedge clk) disable iff (!rst_n) (rd_en && !empty) ##1 1'b1);
  c_rd_empty_then_wr: cover property (@(posedge clk) disable iff (!rst_n)
                   (empty && rd_en && !wr_en) ##1 (wr_en && !rd_en));

endmodule
