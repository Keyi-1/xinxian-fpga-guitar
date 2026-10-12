set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
set repo_root [file normalize [file join $project_dir ../..]]
foreach source {
    rtl/top/neo_lcd_lissajous_top.v
    rtl/display/lcd_rgb_scan_480x272.v
    rtl/display/lcd_lissajous_renderer.v
    rtl/display/lcd_lissajous_ram.v
    rtl/display/lcd_lissajous_sine.v
    rtl/display/lcd_neon_palette.v
} { add_file -type verilog [file join $repo_root $source] }
add_file -type cst [file join $repo_root constraints neo_lcd_lissajous.cst]
add_file -type sdc [file join $repo_root constraints neo_lcd_lissajous.sdc]
set_device -name GW5AT-60B GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module neo_lcd_lissajous_top
set_option -verilog_std v2001
set_option -output_base_name neo_lcd_lissajous
set_option -use_i2c_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
run all
