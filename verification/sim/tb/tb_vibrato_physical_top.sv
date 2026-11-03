// ID70 integration coverage derived from tb_posture_top.sv; identical controls/audio scenarios.
`timescale 1ns/1ps
// Actual production top and real MPU I2C pins. Only touch/ADC registered event
// outputs and the millisecond stimulus are accelerated; audio sample clock,
// sample equations, mode release, UART engine and all synthesis are unchanged.
module tb_vibrato_physical_top;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg click=0,dbl=0,key_n=1,fast_ms=0,nak=0;
    reg [8:0] cx=0,cy=0;
    reg [3:0] pluck=0;
    integer divider=0;
    always @(negedge clk)begin fast_ms=divider==499;divider=fast_ms ? 0 : divider+1;end
    tri1 scl,sda,ctp_scl,ctp_sda,ctp_int;
    tri [3:0] row;
    reg [15:0] pressed_frets=16'h3333;
    function [7:0] physical_columns(input [3:0] rows,input [15:0] fret_word);
        integer string_index;
        reg [7:0] columns;
        begin
            columns=8'hff;
            for(string_index=0;string_index<4;string_index=string_index+1)
                if(rows[string_index]===1'b0 && fret_word[string_index*4+:4]>0 && fret_word[string_index*4+:4]<=8)
                    columns=columns & ~(8'd1<<(fret_word[string_index*4+:4]-1));
            physical_columns=columns;
        end
    endfunction
    wire [7:0] columns=physical_columns(row,pressed_frets);
    reg [111:0] packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
    wire [31:0] writes,bursts;
    integer samples=0,attacks=0,auto_changes=0,step=0;
    neo_guitar_touch_game_top #(.KEY_DEBOUNCE_CYCLES(4),.MATRIX_CLK_DIV(2),.MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(1),.ADC_SPI_CLK_DIV(1),.IMU_I2C_QUARTER(5),
        .IMU_CALIBRATION_LOG2(3),.IMU_HEALTH_MS(30),.IMU_STABLE_MS(40),.IMU_COOLDOWN_MS(80)) dut(
        .audio_clk_12m288(ac),.sys_clk_50m(clk),.USER_BUTTON1_n(key_n),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1),
        .ROW0(row[0]),.ROW1(row[1]),.ROW2(row[2]),.ROW3(row[3]),
        .COL0(columns[0]),.COL1(columns[1]),.COL2(columns[2]),.COL3(columns[3]),.COL4(columns[4]),.COL5(columns[5]),.COL6(columns[6]),.COL7(columns[7]),
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
        if(dut.u_audio.u_chain.deadline_miss || dut.u_audio.u_chain.performance_vibrato.deadline_miss)$fatal(1,"FAIL: audio deadline");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    task tap(input integer x,y);
        @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(20)@(negedge clk);
    endtask
    task press;
        @(negedge ac);key_n=0;repeat(20)@(negedge ac);key_n=1;repeat(20)@(negedge ac);
    endtask
    task wait_ms(input integer n);repeat(n*500)@(negedge clk);endtask
    task wait_samples(input integer count);
        integer observed;
        begin
            observed=0;
            while(observed<count)begin
                @(negedge ac);
                if(dut.u_audio.sample_tick)observed=observed+1;
            end
        end
    endtask
    integer gesture_index;
    reg [127:0] phase_before,held_target_before;
    initial begin
        force dut.u_touch.ready=1'b1;
        force dut.u_gesture.click=click;force dut.u_gesture.double_click=dbl;
        force dut.u_gesture.click_x=cx;force dut.u_gesture.click_y=cy;
        force dut.tick_ms=fast_ms;
        force dut.u_audio.pluck_valid=pluck;force dut.u_audio.velocity=8'haa;
        wait(dut.lcd_rst_n);wait(dut.posture.imu_ready);step=1;
        tap(60,255);wait(dut.posture.calibrated && dut.posture.healthy);
        tap(120,150);wait(dut.page==1);step=2;
        wait(dut.u_audio.fret_id==16'h3333);
        @(negedge ac);pluck=15;@(negedge ac);pluck=0;
        wait(dut.posture_voice_active==15);wait_samples(100);
        for(gesture_index=0;gesture_index<3;gesture_index=gesture_index+1)begin
            held_target_before=dut.u_audio.target_phase;
            pressed_frets=0;wait(dut.u_audio.fret_id==0);wait_samples(3000);
            check(dut.u_audio.performance_vibrato==0,"release immediately cancels vibrato");
            check(dut.u_audio.target_phase==held_target_before,"physical release retains the fretted targets");
            pressed_frets=16'h3333;wait(dut.u_audio.fret_id==16'h3333);wait_samples(1100);
        end
        step=3;check(dut.u_audio.performance_vibrato==15,"three physical matrix taps enable all four independent voices");
        check(attacks==1,"matrix gestures never create another Attack");
        wait(dut.u_audio.u_chain.performance_vibrato.enabled==15);
        phase_before=dut.u_audio.audible_phase;
        wait_samples(9000);
        check(dut.u_audio.audible_phase!=phase_before,"actual vibrato remains audible over a complete LFO cycle");
        pressed_frets=16'h3334;wait(dut.u_audio.fret_id==16'h3334);wait_samples(2);
        check(dut.u_audio.performance_vibrato==14,"changing one fret cancels only that string");
        @(negedge ac);pluck=2;@(negedge ac);pluck=0;wait_samples(4);
        check(dut.u_audio.performance_vibrato==12,"real restrike cancels only its string");
        step=4;@(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(dut.page==0);
        check(dut.u_audio.performance_vibrato==0,"exit clears gesture and modulation");
        tap(340,150);wait(dut.page==2);tap(100,70);wait(dut.page==3);
        tap(120,220);wait(dut.u_audio.mode==2 && !dut.u_audio.switching);
        check(dut.u_audio.performance_vibrato==0,"game countdown never enables performance vibrato");
        wait_samples(64);step=5;
        @(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(dut.page==0);
        check(bursts>10,"physical ID70 samples continue during vibrato");
        $display("PASS: full production RTL vibrato, physical four-string columns/three production-timed taps/held pitch/independent cancel/restrike/game/exit; %0d audio samples %0d MPU bursts",samples,bursts);$finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: P4 top watchdog step%0d page%0d mode%0d pose%0d tone%0d auto%0b healthy%0b pending%0b quiet%0d enabled%0b busy%0b active%h guard%h",step,dut.page,dut.u_audio.mode,dut.posture.stable_pose,dut.timbre_mode,dut.posture.auto_enable,dut.posture.healthy,dut.posture.pending,dut.posture.policy.quiet,dut.posture.policy.enabled,dut.posture_timbre_busy,dut.posture_voice_active,dut.posture_note_guard);end
endmodule
