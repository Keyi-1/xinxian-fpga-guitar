set rtl_files [concat \
    [glob rtl/audio_io/*.v] \
    [glob rtl/control/*.v] \
    [glob rtl/display/*.v] \
    [glob rtl/input/*.v] \
    [glob rtl/synth/*.v] \
    [glob rtl/top/*.v]]

add_file -type verilog {*}$rtl_files
add_file -type sdc constraints/full_timing.sdc
set_device GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module full_guitar_top
set_option -verilog_std v2001
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
set_option -output_base_name full_guitar_top
run syn
