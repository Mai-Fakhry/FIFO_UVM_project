vlib work
vlog -f src_files.list +cover -covercells
vsim -voptargs=+acc work.FIFO_TOP -cover -classdebug -uvmcontrol=all -onfinish stop +UVM_TESTNAME=FIFO_main_test
add wave /FIFO_TOP/FIFO_if/*
add wave /FIFO_TOP/fifo_dut/count /FIFO_TOP/fifo_dut/wr_ptr /FIFO_TOP/fifo_dut/rd_ptr
run -all
coverage exclude -src FIFO.sv -line 89 -code b -allfalse -comment "implicit else unreachable: full/empty/neither cover every state"
coverage save FIFO_cov.ucdb
coverage report -details -du=FIFO -output code_coverage.txt
coverage report -details -cvg -output functional_coverage.txt
coverage report -details -assert -directive -output sequential_domain_coverage.txt
