# =============================================================================
#  wave.do : waveform layout used for all the snippets in the report
#  (analog-style 'unsigned' for data, binary for flags, groups for readability)
# =============================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {CLOCK / RESET}
add wave -noupdate -label clk    /FIFO_TOP/FIFO_if/clk
add wave -noupdate -label rst_n  /FIFO_TOP/FIFO_if/rst_n
add wave -noupdate -divider {DRIVEN BY UVM DRIVER}
add wave -noupdate -label wr_en    /FIFO_TOP/FIFO_if/wr_en
add wave -noupdate -label rd_en    /FIFO_TOP/FIFO_if/rd_en
add wave -noupdate -label data_in  -radix hexadecimal /FIFO_TOP/FIFO_if/data_in
add wave -noupdate -divider {DUT OUTPUTS}
add wave -noupdate -label data_out -radix hexadecimal /FIFO_TOP/FIFO_if/data_out
add wave -noupdate -label wr_ack      /FIFO_TOP/FIFO_if/wr_ack
add wave -noupdate -label overflow    /FIFO_TOP/FIFO_if/overflow
add wave -noupdate -label underflow   /FIFO_TOP/FIFO_if/underflow
add wave -noupdate -label full        /FIFO_TOP/FIFO_if/full
add wave -noupdate -label almostfull  /FIFO_TOP/FIFO_if/almostfull
add wave -noupdate -label almostempty /FIFO_TOP/FIFO_if/almostempty
add wave -noupdate -label empty       /FIFO_TOP/FIFO_if/empty
add wave -noupdate -divider {DUT INTERNALS}
add wave -noupdate -label count  -radix unsigned /FIFO_TOP/fifo_dut/count
add wave -noupdate -label wr_ptr -radix unsigned /FIFO_TOP/fifo_dut/wr_ptr
add wave -noupdate -label rd_ptr -radix unsigned /FIFO_TOP/fifo_dut/rd_ptr
add wave -noupdate -divider {ASSERTIONS (bound)}
add wave -noupdate -r /FIFO_TOP/fifo_dut/u_fifo_sva/a_*
configure wave -namecolwidth 150
configure wave -valuecolwidth 70
configure wave -timelineunits ns
update
