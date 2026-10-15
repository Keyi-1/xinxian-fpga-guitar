create_clock -name audio_clk_12m288 -period 81.380208 [get_ports {audio_clk_12m288}]
create_clock -name sys_clk_50m -period 20.000 [get_ports {sys_clk_50m}]
set_clock_groups -asynchronous -group [get_clocks {audio_clk_12m288}] -group [get_clocks {sys_clk_50m}]
set_false_path -from [get_ports {USER_BUTTON1_n USER_BUTTON2_n USER_BUTTON3_n}]
# The audio/display crossing is the coherent held-data/toggle mailbox.
# RGB/DE/sync are registered at falling DCLK, 60 ns before rising.

# Registered serial outputs: bound each pin delay to 40 ns. With 162.76 ns
# nominal half-BCLK, worst-case clock/data skew remains below 40 ns.
# This leaves >122 ns receiver setup/hold before cable/module effects.
set_max_delay 40.000 -to [get_ports {i2s_bclk i2s_ws i2s_data}]

# Touch bus inputs are synchronized before state decisions.
set_false_path -from [get_ports {ctp_scl ctp_sda ctp_int}]
