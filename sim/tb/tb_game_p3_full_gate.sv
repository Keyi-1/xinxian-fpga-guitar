`timescale 1ns/1ps
// Full original-project synthesized VG versus full current RTL. External
// UART is real115200; touch events are registered-output stimulus. Only the
// checked32 countdown Q registers are held at zero to shorten the countdown.
module tb_game_p3_full_gate;
    GSR GSR(.GSRI(1'b1));
    localparam BIT=434;
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg rx=1,click=0,dbl=0;reg [8:0] cx=0,cy=0;
    wire tx,rtx;wire rst=reference.lcd_rst_n;
    tri1 gscl,gsda,gint,rscl,rsda,rint,giscl,gisda,riscl,risda;tri [3:0] grow,rrow;
    wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl,grst,rrst;
    wire [5:0] gr,gg,gb,rr,rg,rb;wire [6:0] gaudio,raudio;
    integer rx_count=0,packets=0,samples=0,frames=0,pixels=0,attacks=0,last_frame;
    reg [7:0] received[0:4095];
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk), \
        .USER_BUTTON1_n(1'b1),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),.COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(rx)
    neo_guitar_touch_game_top gate(`COMMON,.song_uart_tx(tx),
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),
        .i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb),
        .ctp_scl(gscl),.ctp_sda(gsda),.ctp_int(gint),.ctp_rst_n(grst),.imu_scl(giscl),.imu_sda(gisda));
    rtlref_neo_guitar_touch_game_top reference(`COMMON,.song_uart_tx(rtx),
        .ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]),
        .dac_bclk(raudio[0]),.dac_lrck(raudio[1]),.dac_din(raudio[2]),.pa_en_n(raudio[3]),
        .i2s_bclk(raudio[4]),.i2s_ws(raudio[5]),.i2s_data(raudio[6]),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb),
        .ctp_scl(rscl),.ctp_sda(rsda),.ctp_int(rint),.ctp_rst_n(rrst),.imu_scl(riscl),.imu_sda(risda));
    `undef COMMON
    `include "game_p3_uart_host.vh"
    always @(posedge clk)begin
        #2;
        if(rst)begin
            if(tx!==rtx)$fatal(1,"FAIL: actual VG UART TX differs from RTL");
            if(gaudio!==raudio)$fatal(1,"FAIL: actual VG PT8211/I2S/PA differs, sample%0d",samples);
            if(reference.u_display.initialized)begin
                if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})
                    $fatal(1,"FAIL: actual VG LCD differs, pixels%0d time%0t",pixels,$time);
                if(rd && rp)pixels=pixels+1;
                if(reference.frame_begin)frames=frames+1;
            end
            if(gate.u_ui.page_Z!==reference.page)$fatal(1,"FAIL: actual UI page mismatch");
        end
    end
    always @(negedge ac)if(reference.audio_rst_n)begin
        if(reference.u_audio.sample_tick)samples=samples+1;
        if(reference.u_audio.note_on!=0)begin
            if(reference.u_audio.note_on!==4'b1111 || reference.u_audio.target_phase!==
                {32'd46819719,32'd29494575,32'd13138339,32'd70150316} || reference.u_audio.note_velocity!==8'haa)
                $fatal(1,"FAIL: imported four-voice G5/D3/E4/C5 golden phases/velocities");
            attacks=attacks+4;
        end
        if(|reference.u_audio.u_chain.deadline_miss || reference.audio_game_snapshot[234])$fatal(1,"FAIL: reference deadline");
    end
    task automatic tap(input integer x,y);
        begin @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(40)@(negedge clk);end
    endtask
    reg [127:0] events[0:3];reg [31:0] song_crc;integer event_index;
    initial begin
        `include "p3_gate_touch.vh"
        wait(rst);repeat(40)@(negedge clk);tap(340,150);
        if(reference.page!=2)$fatal(1,"FAIL: gate song menu");
        events[0]={16'd0,16'hbeef,8'd0,8'd0,8'd0,8'd79,32'd128,32'd0};
        events[1]={16'd0,16'h1234,8'd0,8'd1,8'd1,8'd50,32'd128,32'd0};
        events[2]={16'd0,16'habcd,8'd0,8'd2,8'd2,8'd64,32'd128,32'd0};
        events[3]={16'd0,16'hffff,8'd0,8'd3,8'd3,8'd72,32'd128,32'd0};
        song_crc=32'hffffffff;
        for(event_index=0;event_index<4;event_index=event_index+1)song_crc=crc_record(song_crc,events[event_index]);
        song_crc=song_crc^32'hffffffff;
        transact(1,321,0,0,0);
        transact(3,321,1,{32'd0,song_crc,32'd1024,16'd4,8'd1,8'd4},0);
        transact(4,321,2,events[0],0);transact(4,321,2,events[0],0);
        for(event_index=1;event_index<4;event_index=event_index+1)transact(4,321,2+event_index,events[event_index],0);
        transact(5,321,6,0,0);transact(2,321,7,128'd4,0);
        if(last_reply[50:40]!=703 || last_reply[62:51]!=4)$fatal(1,"FAIL: gate LIST imported extent");
        tap(100,240);if(reference.page!=3)$fatal(1,"FAIL: gate fifth touch row");
        tap(340,220);
        wait(reference.u_audio.p2.u_router.engine.controller.countdown);
        `include "p3_gate_countdown.vh"
        wait(reference.page==5);
        if(reference.timbre_mode!=1)$fatal(1,"FAIL: gate recommended timbre");
        transact(3,321,8,{32'd0,song_crc,32'd1024,16'd4,8'd1,8'd4},1);
        wait(reference.page==6);
        if(attacks!=4 || reference.display_fault)$fatal(1,"FAIL: gate imported preview completion");
        tap(350,230);tap(100,150);wait(reference.page==1 && !reference.transition);
        last_frame=frames;wait(frames>=last_frame+2);
        if(pixels<500000 || samples<2000)$fatal(1,"FAIL: insufficient actual scan/audio coverage");
        $display("PASS: full actual VG vs full RTL, %0d real115200 UART request/ACK packets incl duplicate/BUSY, actual DPB write+RAM-readback CRC/group/all4 velocity metadata+dual-clock commit, fifth touch row/second timbre/four voices G5-D3-E4-C5 real decode+existing preview velocity2/audio/exit, %0d audio samples and %0d LCD clock samples across %0d frames incl spectrum/curve fade; no ROM/phase/launch injection; only registered touch stimulus and checked32 countdown Q",packets,samples,pixels,frames);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"FAIL: P3 actual gate watchdog");end
endmodule
