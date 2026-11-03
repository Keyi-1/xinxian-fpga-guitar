// ID70 integration coverage derived from tb_posture_full_gate.sv; identical controls/audio scenarios.
`timescale 1ns/1ps
// Complete actual synthesized top versus current full RTL, with physical MPU
// bus models and physical tone key. Only audited timer Q/touch/ADC boundaries
// are stimulated. Production256 calibration and all audio clocks stay intact.
module tb_vibrato_full_gate;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg click=0,dbl=0,key_n=1,nak=0;reg [8:0] cx=0,cy=0;reg [3:0] pluck=0;
    wire rst=reference.lcd_rst_n;
    reg [8:0] ms_phase=0;reg [2:0] bus_phase=0;
    wire [15:0] accelerated_ms_count=ms_phase==499 ? 16'd49999 : {7'd0,ms_phase};
    wire [31:0] accelerated_i2c_count=bus_phase==4 ? 32'd124 : {29'd0,bus_phase};
    always @(negedge clk)begin
        if(!rst)begin ms_phase=0;bus_phase=0;end
        else begin ms_phase=ms_phase==499 ? 0 : ms_phase+1'b1;bus_phase=bus_phase==4 ? 0 : bus_phase+1'b1;end
    end
    tri1 gscl,gsda,rscl,rsda,gtscl,gtsda,gtint,rtscl,rtsda,rtint;
    tri [3:0] grow,rrow;
    wire [6:0] gaudio,raudio;
    wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl;
    wire [5:0] gr,gg,gb,rr,rg,rb;
    reg [111:0] packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
    wire [31:0] gwrites,gbursts,rwrites,rbursts;
    integer samples=0,frames=0,lcd_clocks=0,attacks=0,changes=0,step=0;
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
    wire [7:0] gcolumns=physical_columns(grow,pressed_frets);
    wire [7:0] rcolumns=physical_columns(rrow,pressed_frets);
    reg old_p=0;reg [1:0] previous_tone=0;
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk), \
        .USER_BUTTON1_n(key_n),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(1'b1),.song_uart_tx(),.ctp_rst_n()
    neo_guitar_touch_game_top gate(`COMMON,.COL0(gcolumns[0]),.COL1(gcolumns[1]),.COL2(gcolumns[2]),.COL3(gcolumns[3]),.COL4(gcolumns[4]),.COL5(gcolumns[5]),.COL6(gcolumns[6]),.COL7(gcolumns[7]),.imu_scl(gscl),.imu_sda(gsda),
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),
        .i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb),
        .ctp_scl(gtscl),.ctp_sda(gtsda),.ctp_int(gtint));
    rtlref_neo_guitar_touch_game_top reference(`COMMON,.COL0(rcolumns[0]),.COL1(rcolumns[1]),.COL2(rcolumns[2]),.COL3(rcolumns[3]),.COL4(rcolumns[4]),.COL5(rcolumns[5]),.COL6(rcolumns[6]),.COL7(rcolumns[7]),.imu_scl(rscl),.imu_sda(rsda),
        .ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]),
        .dac_bclk(raudio[0]),.dac_lrck(raudio[1]),.dac_din(raudio[2]),.pa_en_n(raudio[3]),
        .i2s_bclk(raudio[4]),.i2s_ws(raudio[5]),.i2s_data(raudio[6]),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb),
        .ctp_scl(rtscl),.ctp_sda(rtsda),.ctp_int(rtint));
    `undef COMMON
    mpu6050_test_slave #(.WHO_AM_I(8'h70)) gslave(.scl(gscl),.sda(gsda),.rst_n(rst),.nak(nak),.bad_id(1'b0),.bad_config(1'b0),.data_ready(1'b1),.packet(packet),.writes(gwrites),.bursts(gbursts));
    mpu6050_test_slave #(.WHO_AM_I(8'h70)) rslave(.scl(rscl),.sda(rsda),.rst_n(rst),.nak(nak),.bad_id(1'b0),.bad_config(1'b0),.data_ready(1'b1),.packet(packet),.writes(rwrites),.bursts(rbursts));
    always @(posedge clk)begin
        #2;
        if(rst)begin
            if(gaudio!==raudio)$fatal(1,"FAIL: P4 VG audio/PT8211/I2S/PA differs step%0d",step);
            if({gscl,gsda}!=={rscl,rsda})$fatal(1,"FAIL: P4 VG MPU open-drain GPIO differs step%0d",step);
            if(gate.u_buttons.timbre_mode_Z!==reference.timbre_mode)$fatal(1,"FAIL: actual tone enum differs");
            if(reference.u_display.initialized)begin
                if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})$fatal(1,"FAIL: P4 VG LCD differs step%0d",step);
                if(rd)lcd_clocks=lcd_clocks+1;
                if(!old_p && rp && !rh && !rv)frames=frames+1;
                old_p=rp;
            end
        end
    end
    always @(negedge ac)if(reference.audio_rst_n)begin
        if(reference.u_audio.sample_tick)samples=samples+1;
        if(reference.u_audio.note_on)attacks=attacks+1;
        if(previous_tone!=reference.timbre_mode)begin changes=changes+1;previous_tone=reference.timbre_mode;end
        if(reference.u_audio.u_chain.deadline_miss || reference.posture.math_deadline || reference.u_audio.u_chain.performance_vibrato.deadline_miss)$fatal(1,"FAIL: P4 audio/math deadline");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    task tap(input integer x,y);
        @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(20)@(negedge clk);
    endtask
    task press;
        @(negedge ac);key_n=0;repeat(245780)@(negedge ac);key_n=1;repeat(245780)@(negedge ac);
    endtask
    task wait_ms(input integer n);repeat(n*500)@(negedge clk);endtask
    task wait_samples(input integer count);
        integer observed;
        begin
            observed=0;
            while(observed<count)begin
                @(negedge ac);
                if(reference.u_audio.sample_tick)observed=observed+1;
            end
        end
    endtask
    integer gesture_index;
    reg [127:0] phase_before,held_target_before;
    initial begin
        `include "p3_gate_touch.vh"
        `include "p4_gate_acceleration.vh"
        wait(rst);wait(reference.posture.imu_ready);step=1;
        tap(60,255);wait(reference.posture.calibrated && reference.posture.healthy);
        tap(120,150);wait(reference.page==1);step=2;
        wait(reference.u_audio.fret_id==16'h3333);
        @(negedge ac);pluck=15;@(negedge ac);pluck=0;
        wait(reference.posture_voice_active==15);wait_samples(100);
        for(gesture_index=0;gesture_index<3;gesture_index=gesture_index+1)begin
            held_target_before=reference.u_audio.target_phase;
            pressed_frets=0;wait(reference.u_audio.fret_id==0);wait_samples(3000);
            check(reference.u_audio.performance_vibrato==0,"release immediately cancels vibrato");
            check(reference.u_audio.target_phase==held_target_before,"physical release retains the fretted targets");
            pressed_frets=16'h3333;wait(reference.u_audio.fret_id==16'h3333);wait_samples(1100);
        end
        step=3;check(reference.u_audio.performance_vibrato==15,"three physical matrix taps enable all four independent voices");
        check(attacks==1,"matrix gestures never create another Attack");
        wait(reference.u_audio.u_chain.performance_vibrato.enabled==15);
        phase_before=reference.u_audio.audible_phase;
        wait_samples(9000);
        check(reference.u_audio.audible_phase!=phase_before,"actual vibrato remains audible over a complete LFO cycle");
        pressed_frets=16'h3334;wait(reference.u_audio.fret_id==16'h3334);wait_samples(2);
        check(reference.u_audio.performance_vibrato==14,"changing one fret cancels only that string");
        @(negedge ac);pluck=2;@(negedge ac);pluck=0;wait_samples(4);
        check(reference.u_audio.performance_vibrato==12,"real restrike cancels only its string");
        step=4;@(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(reference.page==0);
        check(reference.u_audio.performance_vibrato==0,"exit clears gesture and modulation");
        tap(340,150);wait(reference.page==2);tap(100,70);wait(reference.page==3);
        tap(120,220);wait(reference.u_audio.mode==2 && !reference.u_audio.switching);
        check(reference.u_audio.performance_vibrato==0,"game countdown never enables performance vibrato");
        wait_samples(64);step=5;
        @(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(reference.page==0);
        check(gbursts==rbursts,"real MPU streams remain identical");
        $display("PASS: complete actual vibrato VG versus RTL, physical four-string matrix/three production-timed taps/held pitch/independent cancel/restrike/game/exit; %0d audio samples %0d LCD clock samples %0d MPU bursts",samples,lcd_clocks,gbursts);$finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: P4 full gate watchdog step%0d",step);end
endmodule
