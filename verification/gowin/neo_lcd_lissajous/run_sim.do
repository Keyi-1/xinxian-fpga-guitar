# ModelSim 'do' does not reliably set Tcl 'info script'. Pass the project
# directory as the first macro argument, or launch from this project folder.
if {[info exists 1]} { set project_dir [file normalize $1] } else { set project_dir [pwd] }
if {![file exists [file join $project_dir build.tcl]]} { error "Pass the neo_lcd_lissajous project directory" }
set repo_root [file normalize [file join $project_dir ../..]]
set output_dir [file join $project_dir temp simulation]
file mkdir $output_dir
cd $output_dir
onerror {quit -code 1 -f}
if {![file exists modelsim.ini]} {vmap -c}
if {![file isdirectory demo_work]} {vlib demo_work}
vmap demo_work [file join $output_dir demo_work]
transcript file [file join $output_dir simulation.log]
vlog -sv -work demo_work \
    [file join $repo_root rtl/top/neo_lcd_lissajous_top.v] \
    [file join $repo_root rtl/display/lcd_rgb_scan_480x272.v] \
    [file join $repo_root rtl/display/lcd_lissajous_renderer.v] \
    [file join $repo_root rtl/display/lcd_lissajous_ram.v] \
    [file join $repo_root rtl/display/lcd_lissajous_sine.v] \
    [file join $repo_root rtl/display/lcd_neon_palette.v] \
    [file join $repo_root sim/tb/tb_neo_lcd_lissajous.sv]
vsim -onfinish stop demo_work.tb_neo_lcd_lissajous
run -all
quit -code 0 -f
