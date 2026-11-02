`timescale 1ns/1ps
// Complete current production VG vs RTL. Touch/ADC/button harmony registered outputs are
// explicit stimuli; matrix columns and timbre key use actual top-level pins.
module tb_song_slots_full_gate;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg click=0,dbl=0,key_n=1,harmony_command=0;reg [8:0] cx=0,cy=0;reg [3:0] pluck=0;
    reg [15:0] frets=16'h4321;reg [7:0] velocity=8'he4;
    tri [3:0] grow,rrow;
    tri1 gscl,gsda,gint,rscl,rsda,rint,giscl,gisda,riscl,risda;
    wire [6:0] gaudio,raudio;wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl,grst,rrst;
    wire [5:0] gr,gg,gb,rr,rg,rb;wire tx,rtx;
    integer menu_pixels=0,previews=0,blocked_slots=0;reg previous_menu_pclk=0;
    integer samples=0,pcm_samples=0,pixels=0,attacks=0,harmony_frames=0,root_frames=0,n,k;
    function [7:0] columns(input [3:0] rows);
        integer s;reg [7:0] result;
        begin result=255;for(s=0;s<4;s=s+1)if(rows[s]===0 && frets[s*4+:4]>0)
            result=result & ~(8'd1<<(frets[s*4+:4]-1));columns=result;end
    endfunction
    wire [7:0] gc=columns(grow),rc=columns(rrow);
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk),.USER_BUTTON1_n(key_n),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(1'b1)
    neo_guitar_touch_game_top gate(`COMMON,.COL0(gc[0]),.COL1(gc[1]),.COL2(gc[2]),.COL3(gc[3]),.COL4(gc[4]),.COL5(gc[5]),.COL6(gc[6]),.COL7(gc[7]),
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),.song_uart_tx(tx),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),.i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb),
        .ctp_scl(gscl),.ctp_sda(gsda),.ctp_int(gint),.ctp_rst_n(grst),.imu_scl(giscl),.imu_sda(gisda));
    rtlref_neo_guitar_touch_game_top reference(`COMMON,.COL0(rc[0]),.COL1(rc[1]),.COL2(rc[2]),.COL3(rc[3]),.COL4(rc[4]),.COL5(rc[5]),.COL6(rc[6]),.COL7(rc[7]),
        .ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]),.song_uart_tx(rtx),
        .dac_bclk(raudio[0]),.dac_lrck(raudio[1]),.dac_din(raudio[2]),.pa_en_n(raudio[3]),.i2s_bclk(raudio[4]),.i2s_ws(raudio[5]),.i2s_data(raudio[6]),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb),
        .ctp_scl(rscl),.ctp_sda(rsda),.ctp_int(rint),.ctp_rst_n(rrst),.imu_scl(riscl),.imu_sda(risda));
    `undef COMMON
    always @(posedge clk)begin #2;
        if(reference.lcd_rst_n)begin
            `include "slots_gate_observe.vh"
            if(gaudio!==raudio || tx!==rtx || grow!==rrow)$fatal(1,"VG top audio/UART idle/matrix mismatch sample=%0d",samples);
            if(reference.u_display.initialized)begin
                if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})$fatal(1,"VG display mismatch");
                if(rd && rp)pixels=pixels+1;
                if(rd && rp && !previous_menu_pclk && reference.u_display.u_ui.display_page==2)menu_pixels=menu_pixels+1;
                previous_menu_pclk=rp;
            end
        end
    end
    always @(negedge ac)if(reference.audio_rst_n)begin
        if(reference.u_audio.sample_tick)begin
            samples=samples+1;
            if(reference.u_audio.u_chain.g_piano.u_core.ks_harmony===4'b1111 && reference.u_audio.active===15)harmony_frames=harmony_frames+1;
            if(reference.u_audio.u_chain.g_piano.u_core.ks_harmony===4'b0000)root_frames=root_frames+1;
        end
        if(reference.u_audio.final_pcm_valid)pcm_samples=pcm_samples+1;
        if(|reference.u_audio.u_chain.deadline_miss)$fatal(1,"deadline");
    end
    always @(posedge ac)if(reference.audio_rst_n && reference.u_audio.note_on!=0)attacks=attacks+1;
    task tick;begin @(posedge reference.u_audio.sample_tick);@(negedge ac);end endtask
    reg [95:0] initial_score[0:2047];
    function [26:0] midi_phase;
        input [6:0] midi;
        `include "game_p2_phase.vh"
    endfunction
    task tap(input integer xx,yy);
        @(negedge clk);cx=xx;cy=yy;click=1;@(negedge clk);click=0;repeat(20)@(negedge clk);
    endtask
    task home;
        @(negedge clk);dbl=1;@(negedge clk);dbl=0;
        wait(reference.page==0 && !reference.transition);
    endtask
    integer s,base_expected,count_expected,duration_expected,tone_expected,lane_expected;
    reg [26:0] phase_expected;
    initial begin
        `include "ks_gate_stimulus.vh"
        `include "p3_gate_countdown.vh"
        $readmemh("../../../../mem/game_p3_initial.mem",initial_score);
        wait(reference.lcd_rst_n);repeat(40)@(negedge clk);
        cx=100;cy=150;click=1;@(negedge clk);click=0;
        wait(reference.page==1 && !reference.transition);
        key_n=0;repeat(1100)tick();key_n=1;
        wait(reference.timbre_mode==1 && !reference.u_audio.u_chain.timbre_busy);
        repeat(40)tick();pluck=15;@(negedge ac);pluck=0;
        repeat(4)tick();if(reference.u_audio.active!==15)$fatal(1,"four voices failed to start");
        repeat(100)tick();harmony_command=1;repeat(4)tick();
        pluck=15;@(negedge ac);pluck=0;repeat(480)tick();
        if(reference.u_audio.u_chain.g_piano.u_core.ks_harmony!==15)$fatal(1,"four harmony voices not latched");
        repeat(200)tick();frets=16'h5432;repeat(400)tick();frets=0;repeat(100)tick();
        for(k=0;k<4;k=k+1)begin pluck=1<<k;@(negedge ac);pluck=0;repeat(100)tick();end
        repeat(100)tick();harmony_command=0;repeat(4)tick();
        pluck=15;@(negedge ac);pluck=0;repeat(256)tick();
        if(reference.u_audio.u_chain.g_piano.u_core.ks_harmony!==0)$fatal(1,"harmony did not turn off on strike");
        wait(pixels>=100000);repeat(40)tick();
        $display("coverage: sample=%0d PCM=%0d attacks=%0d pixels=%0d",samples,pcm_samples,attacks,pixels);
        if(samples<3000 || pcm_samples<3000 || attacks<7 || pixels<100000 || harmony_frames<500 || root_frames<1000)$fatal(1,"insufficient full gate coverage");
        $display("harmony coverage: on=%0d off=%0d",harmony_frames,root_frames);
        home();tap(340,150);wait(reference.page==2);
        wait(menu_pixels>=130560);
        for(s=0;s<3;s=s+1)begin
            tap(100,70+s*44);if(reference.page!=3 || reference.selected_slot!=s)$fatal(1,"FAIL: visible builtin slot selection");
            base_expected=s==0 ? 0 : s==1 ? 67 : 235;
            count_expected=s==0 ? 67 : s==1 ? 168 : 212;
            duration_expected=s==0 ? 1620000 : s==1 ? 9216000 : 7296000;
            tone_expected=s==0 ? 0 : s==1 ? 2 : 1;
            lane_expected=initial_score[base_expected][72:71];
            phase_expected=midi_phase(initial_score[base_expected][70:64]);
            tap(340,220);
            wait(reference.u_audio.note_on!=0);
            if(reference.u_audio.note_on!==(1<<lane_expected) || reference.u_audio.target_phase[lane_expected*32+:32]!=={5'd0,phase_expected})
                $fatal(1,"FAIL: retained first note/lane in slot%0d",s);
            if(reference.u_audio.p2.u_router.engine.active_base!=base_expected || reference.u_audio.p2.u_router.engine.active_count!=count_expected ||
               reference.u_audio.p2.u_router.engine.active_duration!=duration_expected || reference.timbre_mode!=tone_expected)
                $fatal(1,"FAIL: playback metadata/tone slot%0d",s);
            previews=previews+1;repeat(128)tick();home();tap(340,150);wait(reference.page==2);
        end
        for(s=3;s<5;s=s+1)begin
            tap(100,70+s*44);if(reference.page!=2 || reference.u_audio.mode!=0)$fatal(1,"FAIL: pending slot playable");
            blocked_slots=blocked_slots+1;
        end
        $display("slots coverage: unique_menu_pixels=%0d builtin_previews=%0d pending_blocked=%0d",menu_pixels,previews,blocked_slots);
        if(menu_pixels<130560 || previews!=3 || blocked_slots!=2)$fatal(1,"FAIL: slots coverage");
        $display("PASS: new slots actual VG vs RTL, first3 builtins and pending4/5;  %0d frames/%0d PCM/%0d LCD clocks, four simultaneous KS voices then independent strikes, real PLL/I2S/matrix/key, registered touch/ADC/harmony-command stimuli only",samples,pcm_samples,pixels);$finish;
    end
    initial begin #500000000;$fatal(1,"full gate watchdog");end
endmodule
