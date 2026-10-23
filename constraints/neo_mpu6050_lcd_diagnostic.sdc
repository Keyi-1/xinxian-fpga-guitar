create_clock -name sys_clk_50m -period 20.000 [get_ports {sys_clk_50m}]
# First-stage GPIO input synchronizers receive asynchronous I2C levels.
set_false_path -from [get_ports {imu_scl imu_sda}]
