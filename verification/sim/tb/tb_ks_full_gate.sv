`timescale 1ns/1ps
// Complete current production VG vs RTL. Touch/ADC registered outputs are
// explicit stimuli; matrix columns and timbre key use actual top-level pins.
module tb_ks_full_gate;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg click=0,dbl=0,key_n=1;reg [8:0] cx=0,cy=0;reg [3:0] pluck=0;
    reg [15:0] frets=16'h4321;reg [7:0] velocity=8'he4;
    tri [3:0] grow,rrow;
    tri1 gscl,gsda,gint,rscl,rsda,rint,giscl,gisda,riscl,risda;
    wire [6:0] gaudio,raudio;wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl,grst,rrst;
    wire [5:0] gr,gg,gb,rr,rg,rb;wire tx,rtx;
    integer samples=0,pcm_samples=0,pixels=0,attacks=0,n,k;
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
            if(gaudio!==raudio || tx!==rtx || grow!==rrow)$fatal(1,"VG top audio/UART idle/matrix mismatch sample=%0d",samples);
            if(reference.u_display.initialized)begin
                if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})$fatal(1,"VG display mismatch");
                if(rd && rp)pixels=pixels+1;
            end
        end
    end
    always @(negedge ac)if(reference.audio_rst_n)begin
        if(reference.u_audio.sample_tick)samples=samples+1;
        if(reference.u_audio.final_pcm_valid)pcm_samples=pcm_samples+1;
        if(|reference.u_audio.u_chain.deadline_miss)$fatal(1,"deadline");
    end
    always @(posedge ac)if(reference.audio_rst_n && reference.u_audio.note_on!=0)attacks=attacks+1;
    task tick;begin @(posedge reference.u_audio.sample_tick);@(negedge ac);end endtask
    initial begin
        `include "ks_gate_stimulus.vh"
        wait(reference.lcd_rst_n);repeat(40)@(negedge clk);
        cx=100;cy=150;click=1;@(negedge clk);click=0;
        wait(reference.page==1 && !reference.transition);
        key_n=0;repeat(1100)tick();key_n=1;
        wait(reference.timbre_mode==1 && !reference.u_audio.u_chain.timbre_busy);
        repeat(40)tick();pluck=15;@(negedge ac);pluck=0;
        repeat(4)tick();if(reference.u_audio.active!==15)$fatal(1,"four voices failed to start");
        repeat(200)tick();frets=16'h5432;repeat(400)tick();frets=0;repeat(100)tick();
        for(k=0;k<4;k=k+1)begin pluck=1<<k;@(negedge ac);pluck=0;repeat(100)tick();end
        repeat(100)tick();
        wait(pixels>=100000);repeat(40)tick();
        $display("coverage: sample=%0d PCM=%0d attacks=%0d pixels=%0d",samples,pcm_samples,attacks,pixels);
        if(samples<2200 || pcm_samples<2200 || attacks<5 || pixels<100000)$fatal(1,"insufficient full gate coverage");
        $display("PASS: full actual VG vs RTL, %0d frames/%0d PCM/%0d LCD clocks, four simultaneous KS voices then independent strikes, real PLL/I2S/matrix/key, registered touch/ADC stimuli only",samples,pcm_samples,pixels);$finish;
    end
    initial begin #500000000;$fatal(1,"full gate watchdog");end
endmodule
