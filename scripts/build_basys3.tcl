# Build only: does not connect to or program any physical board.
# vivado -mode batch -source scripts/build_basys3.tcl
set root_dir [file normalize [file join [file dirname [info script]] ..]]
set out_dir [file join $root_dir build basys3]
file mkdir $out_dir
create_project -in_memory -part xc7a35tcpg236-1
read_verilog -sv [glob [file join $root_dir rtl *.sv]]
read_verilog -sv [file join $root_dir boards basys3 basys3_demo_top.sv]
read_verilog -sv [file join $root_dir boards basys3 basys3_packet_rom.sv]
read_xdc [file join $root_dir boards basys3 basys3.xdc]
synth_design -top basys3_demo_top -part xc7a35tcpg236-1
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq ""} {
        error "Missing board pin assignment for $port; stopping before implementation."
    }
}
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out_dir timing_summary.rpt]
check_timing -verbose -file [file join $out_dir check_timing.rpt]
report_drc -file [file join $out_dir drc.rpt]
report_cdc -file [file join $out_dir cdc.rpt]
write_checkpoint -force [file join $out_dir basys3_demo.dcp]
# Do not create a programming file for a design that fails routed setup/hold.
set worst_setup [get_timing_paths -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst_setup] == 0 || [llength $worst_hold] == 0} { error "No timed setup/hold paths found." }
if {[get_property SLACK $worst_setup] < 0 || [get_property SLACK $worst_hold] < 0} {
    error "Routed timing failed; see timing_summary.rpt. Bitstream not generated."
}
write_bitstream -force [file join $out_dir basys3_demo.bit]
puts "Basys 3 demo bitstream: [file join $out_dir basys3_demo.bit]"
