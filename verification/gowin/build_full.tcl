# Logic/resource verification only: LCD pins are not yet confirmed.
# Use neo_guitar_audio_full/build.tcl for the downloadable three-key audio FULL.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname $script_dir]
set work_dir [file join $script_dir full_main_build]
file mkdir $work_dir
cd $work_dir
# The canonical ROM paths ../../mem now resolve deterministically.
set rtl_files [concat \
    [glob [file join $repo_root rtl audio_io *.v]] \
    [glob [file join $repo_root rtl control *.v]] \
    [glob [file join $repo_root rtl display *.v]] \
    [glob [file join $repo_root rtl input *.v]] \
    [glob [file join $repo_root rtl synth *.v]] \
    [glob [file join $repo_root rtl top *.v]]]
add_file -type verilog {*}$rtl_files
add_file -type sdc [file join $repo_root constraints full_timing.sdc]
set_device GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module full_guitar_top
set_option -verilog_std v2001
set_option -include_path [file join $repo_root rtl config]
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
set_option -output_base_name full_guitar_top
run all
