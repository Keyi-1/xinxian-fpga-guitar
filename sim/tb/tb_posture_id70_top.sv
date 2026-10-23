// ID70 integration coverage derived from tb_posture_top.sv; identical controls/audio scenarios.
`timescale 1ns/1ps
// Actual production top and real MPU I2C pins. Only touch/ADC registered event
// outputs and the millisecond stimulus are accelerated; audio sample clock,
// sample equations, mode release, UART engine and all synthesis are unchanged.
module tb_posture_id70_top;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg click=0,dbl=0,key_n=1,fast_ms=0,nak=0;
    reg [8:0] cx=0,cy=0;
    reg [3:0] pluck=0;
    integer divider=0;
    always @(negedge clk)begin fast_ms=divider==499;divider=fast_ms ? 0 : divider+1;end
    tri1 scl,sda,ctp_scl,ctp_sda,ctp_int;
    tri [3:0] row;
    reg [111:0] packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
    wire [31:0] writes,bursts;
    integer samples=0,attacks=0,auto_changes=0,step=0;
    neo_guitar_touch_game_top #(.KEY_DEBOUNCE_CYCLES(4),.MATRIX_CLK_DIV(2),.MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(1),.ADC_SPI_CLK_DIV(1),.IMU_I2C_QUARTER(5),
        .IMU_CALIBRATION_LOG2(3),.IMU_HEALTH_MS(30),.IMU_STABLE_MS(40),.IMU_COOLDOWN_MS(80)) dut(
        .audio_clk_12m288(ac),.sys_clk_50m(clk),.USER_BUTTON1_n(key_n),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1),
        .ROW0(row[0]),.ROW1(row[1]),.ROW2(row[2]),.ROW3(row[3]),
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),.COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1),
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.dac_bclk(),.dac_lrck(),.dac_din(),.pa_en_n(),
        .event_led(),.lcd_pclk(),.lcd_hsync(),.lcd_vsync(),.lcd_de(),.lcd_backlight(),.lcd_r(),.lcd_g(),.lcd_b(),
        .i2s_bclk(),.i2s_ws(),.i2s_data(),.ctp_scl(ctp_scl),.ctp_sda(ctp_sda),.ctp_int(ctp_int),.ctp_rst_n(),
        .song_uart_rx(1'b1),.song_uart_tx(),.imu_scl(scl),.imu_sda(sda));
    mpu6050_test_slave #(.WHO_AM_I(8'h70)) slave(.scl(scl),.sda(sda),.rst_n(dut.lcd_rst_n),.nak(nak),.bad_id(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.packet(packet),.writes(writes),.bursts(bursts));
    always @(negedge ac)if(dut.audio_rst_n)begin
        if(dut.u_audio.sample_tick)samples=samples+1;
        if(dut.u_audio.note_on)attacks=attacks+1;
        if(dut.auto_timbre_load)begin
            auto_changes=auto_changes+1;
            if(dut.posture_voice_active || dut.posture_note_guard || !dut.posture_performance)$fatal(1,"FAIL: unsafe auto commit");
        end
        if(dut.u_audio.u_chain.deadline_miss)$fatal(1,"FAIL: audio deadline");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    task tap(input integer x,y);
        @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(20)@(negedge clk);
    endtask
    task press;
        @(negedge ac);key_n=0;repeat(20)@(negedge ac);key_n=1;repeat(20)@(negedge ac);
    endtask
    task wait_ms(input integer n);repeat(n*500)@(negedge clk);endtask
    initial begin
        force dut.u_touch.ready=1'b1;
        force dut.u_gesture.click=click;force dut.u_gesture.double_click=dbl;
        force dut.u_gesture.click_x=cx;force dut.u_gesture.click_y=cy;
        force dut.tick_ms=fast_ms;
        force dut.u_audio.pluck_valid=pluck;force dut.u_audio.velocity=8'haa;
        wait(dut.lcd_rst_n);wait(dut.posture.imu_ready);step=1;
        tap(200,255);check(!dut.posture.auto_enable,"AUTO rejected before calibration");
        tap(60,255);wait(dut.posture.calibrated && dut.posture.healthy);wait_ms(70);step=2;
        check(dut.posture.stable_pose==1 && dut.timbre_mode==0 && attacks==0,"calibrated home never plays");
        tap(200,255);check(dut.posture.auto_enable,"explicit AUTO enabled");
        tap(120,150);wait(dut.page==1);step=3;
        packet={16'd0,16'd7100,16'd4100,16'd0,16'd0,16'd0,16'd0};
        wait(dut.timbre_mode==1);step=4;check(attacks==0,"GPIO pose selects actual bright with no pluck");
        press();check(dut.timbre_mode==2,"existing physical key cycles bright to wah");
        wait_ms(500);check(dut.timbre_mode==2,"same guitar pose retains manual wah");
        @(negedge ac);pluck=1;@(negedge ac);pluck=0;wait(dut.posture_voice_active!=0);
        packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
        wait(dut.posture.pending);step=5;check(dut.timbre_mode==2 && dut.posture_voice_active!=0,"automatic piano waits existing tail");
        press();check(dut.timbre_mode==0 && !dut.posture.pending,"manual cancels queued pose");
        packet={16'd0,16'd7100,16'd4100,16'd0,16'd0,16'd0,16'd0};
        wait(dut.posture.pending);step=6;check(dut.timbre_mode==0,"next pose also waits old sound");
        @(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(dut.page==0);
        check(!dut.posture.pending && dut.timbre_mode==0,"normal mode exit cancels pending AUTO");
        tap(120,150);wait(dut.page==1);step=7;wait(dut.timbre_mode==1);step=8;
        nak=1;wait(!dut.posture.healthy);check(dut.timbre_mode==1,"sensor failure retains current choice");
        press();check(dut.timbre_mode==2,"manual remains available offline");
        nak=0;wait(dut.posture.healthy);wait_ms(200);step=9;
        check(dut.timbre_mode==2 && attacks==1,"recovery does not override manual or generate note");
        check(!dut.posture.math_deadline && auto_changes>=2 && bursts>10,"sensor/control complete without math deadline");
        $display("PASS: full production MPU GPIO/touch calibration/AUTO/real tone key/active-tail wait/cancel/exit/re-entry/offline recovery; %0d audio samples %0d MPU bursts %0d actual auto changes",samples,bursts,auto_changes);$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: P4 top watchdog step%0d page%0d mode%0d pose%0d tone%0d auto%0b healthy%0b pending%0b quiet%0d enabled%0b busy%0b active%h guard%h",step,dut.page,dut.u_audio.mode,dut.posture.stable_pose,dut.timbre_mode,dut.posture.auto_enable,dut.posture.healthy,dut.posture.pending,dut.posture.policy.quiet,dut.posture.policy.enabled,dut.posture_timbre_busy,dut.posture_voice_active,dut.posture_note_guard);end
endmodule
