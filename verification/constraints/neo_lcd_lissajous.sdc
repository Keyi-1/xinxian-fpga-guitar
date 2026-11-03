create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
set_false_path -from [get_ports {sys_rst_n key_pattern_n key_pause_n}]
# Registered RGB/DE/HS/VS change at DCLK falling, 60 ns before rising.
# Exact delivered-panel external setup/hold limits remain unconfirmed.
