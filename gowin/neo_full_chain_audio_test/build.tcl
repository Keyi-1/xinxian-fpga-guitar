set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
set src_dir [file join $project_dir src]
add_file -type verilog {*}[glob [file join $src_dir *.v]]
add_file -type cst [file join $src_dir neo_full_chain_audio_test.cst]
add_file -type sdc [file join $src_dir neo_full_chain_audio_test.sdc]
set_device GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module neo_full_chain_audio_test_top
set_option -verilog_std v2001
set_option -include_path $src_dir
set_option -output_base_name neo_full_chain_audio_test
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
run all
