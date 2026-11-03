// User-requested isolated test. No game, UART, touch controller or audio core.
module neo_mpu6050_lcd_diagnostic_top #(
    parameter integer POWER_MS=200,RESET_MS=200,WAKE_MS=50,RETRY_MS=1000
)(input wire sys_clk_50m,inout wire imu_scl,imu_sda,
  output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
  output wire [5:0] lcd_r,lcd_g,lcd_b,output wire pa_en_n);
    reg [15:0] startup=0;
    always @(posedge sys_clk_50m)if(startup!=16'hffff)startup<=startup+1'b1;
    wire rst_n;
    reset_sync resetter(.clk(sys_clk_50m),.arst_n(&startup),.srst_n(rst_n));
    reg [15:0] ms_count;
    wire tick_ms=ms_count==49999;
    always @(posedge sys_clk_50m)begin
        if(!rst_n || tick_ms)ms_count<=0;else ms_count<=ms_count+1'b1;
    end
    wire a68,a69,v68,v69,idle_scl,idle_sda,valid;
    wire [7:0] id68,id69,addr,chip_id,regno,expected,actual;
    wire [3:0] e68,e69,status,error;
    wire [4:0] step,fault_step;
    wire [31:0] count,faults;
    wire [15:0] age;
    wire [95:0] axes;
    mpu_lcd_diag_reader #(.POWER_MS(POWER_MS),.RESET_MS(RESET_MS),.WAKE_MS(WAKE_MS),.RETRY_MS(RETRY_MS)) sensor(
        .clk(sys_clk_50m),.rst_n(rst_n),.tick_ms(tick_ms),.scl(imu_scl),.sda(imu_sda),
        .ack68(a68),.ack69(a69),.id68_valid(v68),.id69_valid(v69),.id68(id68),.id69(id69),
        .selected_address(addr),.selected_id(chip_id),.error68(e68),.error69(e69),.status(status),.last_error(error),
        .step(step),.last_fault_step(fault_step),.last_register(regno),.expected_value(expected),.actual_value(actual),
        .sample_count(count),.fault_count(faults),.sample_age(age),.axes(axes),
        .idle_scl(idle_scl),.idle_sda(idle_sda),.sample_valid(valid));
    wire [8:0] x,y;
    wire active,frame;
    wire [17:0] rgb;
    mpu_lcd_diag_screen screen(.clk(sys_clk_50m),.rst_n(rst_n),.frame_start(frame),
        .x(x),.y(y),.ack68(a68),.ack69(a69),.id68_valid(v68),.id69_valid(v69),
        .id68(id68),.id69(id69),.address(addr),.chip_id(chip_id),.error68(e68),.error69(e69),.status(status),
        .last_error(error),.step(status==1 || status==2 || status==4 || status==5 ? fault_step : step),
        .regno(regno),.expected(expected),.actual(actual),
        .count(count),.faults(faults),.age(age),.axes(axes),.idle_scl(idle_scl),.idle_sda(idle_sda),.rgb(rgb));
    lcd_rgb_scan_480x272 scan(.clk(sys_clk_50m),.rst_n(rst_n),.pixel_rgb(rgb),.pixel_x(x),
        .pixel_y(y),.pixel_active(active),.frame_start(frame),.lcd_pclk(lcd_pclk),
        .lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),.lcd_de(lcd_de),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    assign lcd_backlight=1'b1;
    assign pa_en_n=1'b1;
endmodule
