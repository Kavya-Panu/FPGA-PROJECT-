# Create an editable project without overwriting existing work.
set root_dir [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root_dir build basys3_project]
set project_file [file join $project_dir basys3_demo.xpr]
if {[file exists $project_file]} {
    puts "Project already exists; open $project_file. No files changed."
    return
}
create_project basys3_demo $project_dir -part xc7a35tcpg236-1
add_files [glob [file join $root_dir rtl *.sv]]
add_files [file join $root_dir boards basys3 basys3_demo_top.sv]
add_files [file join $root_dir boards basys3 basys3_packet_rom.sv]
add_files -fileset constrs_1 [file join $root_dir boards basys3 basys3.xdc]
add_files -fileset sim_1 [file join $root_dir boards basys3 tb_basys3_demo.sv]
set_property top basys3_demo_top [get_filesets sources_1]
set_property top tb_basys3_demo [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Editable Basys 3 project: $project_file"
