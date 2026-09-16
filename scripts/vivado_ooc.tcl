# Usage: vivado -mode batch -source scripts/vivado_ooc.tcl -tclargs <exact-part>
# Device-only feasibility check. Does not generate a board bitstream.
if {$argc != 1} { error "Pass the exact Xilinx part from your board documentation." }
set target_part [lindex $argv 0]
set project_root [file normalize [file join [file dirname [info script]] ..]]
set out_dir [file join $project_root build vivado_ooc]
file mkdir $out_dir
create_project -in_memory -part $target_part
read_verilog -sv [glob [file join $project_root rtl *.sv]]
read_xdc [file join $project_root constraints core_ooc.xdc]
synth_design -top tick_to_trade -part $target_part -mode out_of_context
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out_dir timing_summary.rpt]
report_drc -file [file join $out_dir drc.rpt]
check_timing -verbose -file [file join $out_dir check_timing.rpt]
write_checkpoint -force [file join $out_dir tick_to_trade.dcp]
puts "OOC reports are in $out_dir. Inspect timing, unconstrained paths, and DRC before quoting performance."
