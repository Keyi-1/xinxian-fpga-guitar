`timescale 1ns/1ps
// Full production top. Stimulate raw GT911 registered frames, never clicks or
// pose/timbre results. Real MPU GPIO, production256 calibration and all policy
// timing counts remain; only ms/I2C counter waiting is accelerated.
module tb_input_rotation_imu_top #(parameter [7:0] SENSOR_ID=8'h70);
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg raw_frame=0;reg [3:0] raw_count=0;reg [7:0] raw_id=7;
    reg [15:0] raw_x=0,raw_y=0,range_x=480,range_y=272;
    reg nak=0;
    wire rst=reference.lcd_rst_n;
    reg [8:0] ms_phase=0;reg [2:0] bus_phase=0;
    wire [15:0] accelerated_ms_count=ms_phase==499 ? 16'd49999 : {7'd0,ms_phase};
    wire [31:0] accelerated_i2c_count=bus_phase==4 ? 32'd124 : {29'd0,bus_phase};
    always @(negedge clk)begin
        if(!rst)begin ms_phase=0;bus_phase=0;end
        else begin ms_phase=ms_phase==499 ? 0 : ms_phase+1'b1;bus_phase=bus_phase==4 ? 0 : bus_phase+1'b1;end
    end
    tri1 rscl,rsda,rtscl,rtsda,rtint;
    tri [3:0] rrow;
    wire [6:0] raudio;wire rp,rh,rv,rd,rl;
    wire [5:0] rr,rg,rb;
    reg [111:0] packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
    wire [31:0] rwrites,rbursts;
    integer samples=0,lcd_clocks=0,clicks=0,auto_changes=0,step=0,ks_frames=0;
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk), \
        .USER_BUTTON1_n(1'b1),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),.COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(1'b1),.song_uart_tx(),.ctp_rst_n()
    `ifdef ACTUAL_GATE
    rtlref_neo_guitar_touch_game_top reference(`COMMON,
    `else
    neo_guitar_touch_game_top reference(`COMMON,
    `endif
        .imu_scl(rscl),.imu_sda(rsda),.ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]),
        .dac_bclk(raudio[0]),.dac_lrck(raudio[1]),.dac_din(raudio[2]),.pa_en_n(raudio[3]),
        .i2s_bclk(raudio[4]),.i2s_ws(raudio[5]),.i2s_data(raudio[6]),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb),
        .ctp_scl(rtscl),.ctp_sda(rtsda),.ctp_int(rtint));
    mpu6050_test_slave #(.WHO_AM_I(SENSOR_ID)) rslave(.scl(rscl),.sda(rsda),.rst_n(rst),.nak(nak),.bad_id(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.packet(packet),.writes(rwrites),.bursts(rbursts));
    `ifdef ACTUAL_GATE
    tri1 gscl,gsda,gtscl,gtsda,gtint;tri [3:0] grow;
    wire [6:0] gaudio;wire gp,gh,gv,gd,gl;wire [5:0] gr,gg,gb;wire [31:0] gwrites,gbursts;
    neo_guitar_touch_game_top gate(`COMMON,
        .imu_scl(gscl),.imu_sda(gsda),.ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),
        .i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb),
        .ctp_scl(gtscl),.ctp_sda(gtsda),.ctp_int(gtint));
    mpu6050_test_slave #(.WHO_AM_I(SENSOR_ID)) gslave(.scl(gscl),.sda(gsda),.rst_n(rst),.nak(nak),.bad_id(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.packet(packet),.writes(gwrites),.bursts(gbursts));
    always @(posedge clk)begin #2;
        if(rst)begin
            if(gaudio!==raudio || grow!==rrow)$fatal(1,"FAIL: actual VG audio/matrix differs step%0d",step);
            if({gscl,gsda}!=={rscl,rsda})$fatal(1,"FAIL: actual MPU GPIO differs step%0d",step);
            if(reference.u_display.initialized && {gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})
                $fatal(1,"FAIL: actual VG LCD differs step%0d",step);
            `include "input_gate_observe.vh"
        end
    end
    `endif
    `undef COMMON
    always @(posedge clk)begin
        if(rst && rd)lcd_clocks=lcd_clocks+1;
        if(reference.click)clicks=clicks+1;
    end
    always @(negedge ac)if(reference.audio_rst_n)begin
        if(reference.u_audio.sample_tick)begin
            samples=samples+1;
            if(reference.timbre_mode==1)ks_frames=ks_frames+1;
        end
        if(reference.auto_timbre_load)begin
            auto_changes=auto_changes+1;
            if(reference.posture_voice_active || reference.posture_note_guard || !reference.posture_performance)
                $fatal(1,"FAIL: unsafe automatic timbre load");
        end
        if(reference.u_audio.u_chain.deadline_miss || reference.posture.math_deadline)$fatal(1,"FAIL: audio/math deadline");
        if(reference.u_audio.note_on)$fatal(1,"FAIL: sensor or touch generated a spurious note");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s step%0d pose%0d",why,step,reference.posture.stable_pose);endtask
    task report(input integer n,x,y);
        @(negedge clk);raw_count=n;raw_x=x;raw_y=y;raw_frame=1;
        @(negedge clk);raw_frame=0;repeat(60)@(negedge clk);
    endtask
    task wait_ms(input integer n);repeat(n*500)@(negedge clk);endtask
    task tap(input integer logical_x,logical_y);
        report(1,479-logical_x,271-logical_y);wait_ms(20);
        report(0,479-logical_x,271-logical_y);repeat(30)@(negedge clk);
    endtask
    task tilted(input integer x,y,z);
        packet={x[15:0],y[15:0],z[15:0],16'd0,16'd0,16'd0,16'd0};wait_ms(2400);
    endtask
    initial begin
        `include "input_reference_stimulus.vh"
        `ifdef ACTUAL_GATE
        `include "input_gate_stimulus.vh"
        `endif
        wait(rst);wait(reference.posture.imu_ready);step=1;
        // Wrong raw corner must no longer hit the CALIBRATE button.
        report(1,60,255);wait_ms(20);report(0,60,255);
        check(!reference.posture.calibrating,"unrotated raw corner cannot calibrate");wait_ms(300);
        tap(60,255);wait(reference.posture.calibrated && reference.posture.healthy);
        wait(reference.posture.stable_pose==1);step=2;
        check(reference.page==0 && reference.timbre_mode==0,"rotated CALIBRATE keeps home/piano");
        tap(200,255);check(reference.posture.auto_enable,"rotated AUTO button enabled");
        tap(120,150);wait(reference.page==1 && !reference.transition);step=3;
        tilted(-6000,0,5578);
        check(reference.posture.stable_pose==2 && reference.timbre_mode==1,"negative-X tilt actually selects bright KS");step=4;
        tilted(0,0,8192);check(reference.posture.stable_pose==1 && reference.timbre_mode==0,"flat selects piano");
        tilted(0,-7100,4100);check(reference.posture.stable_pose==2 && reference.timbre_mode==1,"negative-Y tilt selects KS");step=5;
        nak=1;wait(!reference.posture.healthy);check(reference.timbre_mode==1,"offline retains current timbre");
        nak=0;wait(reference.posture.healthy);wait_ms(1200);
        check(reference.timbre_mode==1,"recovery preserves selected tone");
        check(clicks>=4 && auto_changes>=3 && rbursts>256 && ks_frames>100 && lcd_clocks>100000,"end-to-end coverage");
        $display("PASS: complete input top ID%h, rotated raw CALIBRATE/AUTO/performance taps, production256 calibration, real MPU GPIO negative-X/Y and flat actual timbre loads, offline/recovery, %0d PCM frames %0d LCD clocks %0d bursts %0d clicks %0d auto changes",SENSOR_ID,samples,lcd_clocks,rbursts,clicks,auto_changes);$finish;
    end
    initial begin #300000000;$fatal(1,"FAIL: input top watchdog step%0d calibrated%0b healthy%0b pose%0d",step,reference.posture.calibrated,reference.posture.healthy,reference.posture.stable_pose);end
endmodule
