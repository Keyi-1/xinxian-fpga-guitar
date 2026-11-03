create_clock -name audio_clk_12m288 -period 81.380208 [get_ports {audio_clk_12m288}]
create_clock -name sys_clk_50m -period 20.000 [get_ports {sys_clk_50m}]
set_clock_groups -asynchronous -group [get_clocks {audio_clk_12m288}] -group [get_clocks {sys_clk_50m}]
set_false_path -from [get_ports {USER_BUTTON1_n USER_BUTTON2_n USER_BUTTON3_n}]
# The audio/display crossing is the coherent held-data/toggle mailbox.
# RGB/DE/sync are registered at falling DCLK, 60 ns before rising.
