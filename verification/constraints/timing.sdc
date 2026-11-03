# Xinxian FPGA Guitar
# Initial timing constraint
# 50 MHz system clock: 20 ns period

create_clock -name sys_clk_50m \
    -period 20.000 \
    [get_ports {sys_clk_50m}]