// ID70 integration coverage derived from tb_posture_full_gate.sv; identical controls/audio scenarios.
`timescale 1ns/1ps
// Complete actual synthesized top versus current full RTL, with physical MPU
// bus models and physical tone key. Only audited timer Q/touch/ADC boundaries
// are stimulated. Production256 calibration and all audio clocks stay intact.
module tb_posture_id70_full_gate;
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
    reg old_p=0;reg [1:0] previous_tone=0;
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk), \
        .USER_BUTTON1_n(key_n),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),.COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(1'b1),.song_uart_tx(),.ctp_rst_n()
    neo_guitar_touch_game_top gate(`COMMON,.imu_scl(gscl),.imu_sda(gsda),
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),
        .i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb),
        .ctp_scl(gtscl),.ctp_sda(gtsda),.ctp_int(gtint));
    rtlref_neo_guitar_touch_game_top reference(`COMMON,.imu_scl(rscl),.imu_sda(rsda),
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
        if(reference.u_audio.u_chain.deadline_miss || reference.posture.math_deadline)$fatal(1,"FAIL: P4 audio/math deadline");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    task tap(input integer x,y);
        @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(20)@(negedge clk);
    endtask
    task press;
        @(negedge ac);key_n=0;repeat(245780)@(negedge ac);key_n=1;repeat(245780)@(negedge ac);
    endtask
    task wait_ms(input integer n);repeat(n*500)@(negedge clk);endtask
    initial begin
        `include "p3_gate_touch.vh"
        `include "p4_gate_acceleration.vh"
        wait(rst);wait(reference.posture.imu_ready);step=1;
        tap(60,255);wait(reference.posture.calibrated && reference.posture.healthy);
        wait(reference.posture.stable_pose==1);step=2;
        check(reference.timbre_mode==0 && attacks==0,"home calibration never plays");
        tap(200,255);check(reference.posture.auto_enable,"explicit calibrated AUTO");
        tap(120,150);wait(reference.page==1);step=3;
        packet={16'd0,16'd7100,16'd4100,16'd0,16'd0,16'd0,16'd0};
        wait(reference.timbre_mode==1);step=4;check(attacks==0,"actual bright selection without attack");
        press();check(reference.timbre_mode==2,"physical tone key enters wah");
        wait_ms(1200);check(reference.timbre_mode==2,"same pose preserves manual wah");
        @(negedge ac);pluck=1;@(negedge ac);pluck=0;wait(reference.posture_voice_active!=0);
        packet={16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0};
        wait(reference.posture.pending);step=5;
        check(reference.timbre_mode==2 && reference.posture_voice_active!=0,"active tail keeps old timbre");
        press();check(reference.timbre_mode==0 && !reference.posture.pending,"physical manual cancels auto");
        packet={16'd0,16'd7100,16'd4100,16'd0,16'd0,16'd0,16'd0};wait(reference.posture.pending);step=6;
        @(negedge clk);dbl=1;@(negedge clk);dbl=0;wait(reference.page==0);
        check(reference.timbre_mode==0 && !reference.posture.pending,"mode exit uses original release and cancels auto");
        tap(120,150);wait(reference.page==1);wait(reference.timbre_mode==1);step=7;
        nak=1;wait(!reference.posture.healthy);check(reference.timbre_mode==1,"offline holds tone");
        press();check(reference.timbre_mode==2,"manual offline");nak=0;
        wait(reference.posture.healthy);wait_ms(1200);step=8;
        check(reference.timbre_mode==2 && attacks==1 && gbursts==rbursts,"recovery no extra attack or manual overwrite");
        $display("PASS: complete actual P4 VG versus RTL, real MPU GPIO/physical tone key/production256 calibration/AUTO/tail/manual/exit/recovery; %0d audio samples %0d LCD clock samples %0d MPU bursts %0d tone changes",samples,lcd_clocks,gbursts,changes);$finish;
    end
    initial begin #500000000;$fatal(1,"FAIL: P4 full gate watchdog step%0d",step);end
endmodule
