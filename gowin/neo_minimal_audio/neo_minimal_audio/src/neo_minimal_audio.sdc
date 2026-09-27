create_clock -name sys_clk_50m -period 20.000 [get_ports {sys_clk_50m}]
create_clock -name audio_clk_12m288 -period 81.380208 [get_ports {audio_clk_12m288}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk_50m}] -group [get_clocks {audio_clk_12m288}]