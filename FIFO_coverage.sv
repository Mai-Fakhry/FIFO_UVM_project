package FIFO_coverage_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import shared_pkg::*;
  import FIFO_seq_item_pkg::*;

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

endpackage
