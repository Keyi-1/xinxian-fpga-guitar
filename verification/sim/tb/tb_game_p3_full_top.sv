`timescale 1ns/1ps
// Actual production top with accelerated UART divider and four-sample
// countdown only. Touch-controller click/ready outputs are a stated stimulus
// boundary; UART, bank writes, CDC, UI, layout, router and audio are real RTL.
module tb_game_p3_full_top;
    GSR GSR(.GSRI(1'b1));
    localparam BIT=24;
    reg clk=0,ac=0;always #10 clk=~clk;always #40.690104 ac=~ac;
    reg rx=1,click=0,dbl=0;reg [8:0] cx=0,cy=0;reg [3:0] pluck=0;
    wire tx;wire rst=dut.lcd_rst_n;
    tri r0,r1,r2,r3;tri1 scl,sda,int_n,imu_scl,imu_sda;
    integer rx_count=0,packets=0,samples=0,nonzero=0,attacks=0,frames=0;
    reg [7:0] received[0:4095];
    wire [31:0] game_time=dut.u_audio.p2.u_router.engine.song_time;
    neo_guitar_touch_game_top #(.UART_CLKS_PER_BIT(BIT),.MATRIX_CLK_DIV(2),.MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(1),.ADC_SPI_CLK_DIV(1)) dut(
        .audio_clk_12m288(ac),.sys_clk_50m(clk),.USER_BUTTON1_n(1'b1),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1),
        .ROW0(r0),.ROW1(r1),.ROW2(r2),.ROW3(r3),.COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),
        .COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1),.adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),
        .dac_bclk(),.dac_lrck(),.dac_din(),.pa_en_n(),.event_led(),.lcd_pclk(),.lcd_hsync(),.lcd_vsync(),.lcd_de(),.lcd_backlight(),
        .lcd_r(),.lcd_g(),.lcd_b(),.i2s_bclk(),.i2s_ws(),.i2s_data(),
        .ctp_scl(scl),.ctp_sda(sda),.ctp_int(int_n),.ctp_rst_n(),.song_uart_rx(rx),.song_uart_tx(tx),.imu_scl(imu_scl),.imu_sda(imu_sda));
    defparam dut.u_audio.p2.u_router.engine.COUNTDOWN_SAMPLES=4;
    `include "game_p3_uart_host.vh"
    always @(negedge ac)if(dut.audio_rst_n)begin
        if(dut.u_audio.sample_tick)samples=samples+1;
        if(dut.final_pcm_valid && dut.final_pcm!=0)nonzero=nonzero+1;
        if(dut.u_audio.note_on!=0)begin
            if(attacks==0 && (dut.u_audio.note_on!==1 || dut.u_audio.target_phase[31:0]!==32'd70150316))
                $fatal(1,"FAIL: imported G5 attack/target %h",dut.u_audio.target_phase[31:0]);
            if(attacks==1 && dut.u_audio.note_on!==2)$fatal(1,"FAIL: imported second lane");
            attacks=attacks+1;
        end
        if(|dut.u_audio.u_chain.deadline_miss || dut.audio_game_snapshot[234])$fatal(1,"FAIL: full-top deadline");
    end
    always @(negedge clk)if(rst && dut.frame_begin)begin
        frames=frames+1;
        if(dut.page==5 && dut.u_display.p2.u_chart.base!=703)$fatal(1,"FAIL: display used frozen catalog for imported slot");
    end
    task automatic tap(input integer x,y);
        begin @(negedge clk);cx=x;cy=y;click=1;@(negedge clk);click=0;repeat(30)@(negedge clk);end
    endtask
    reg [127:0] one,two;reg [31:0] song_crc;
    initial begin
        force dut.touch_ready=1'b1;
        force dut.click=click;force dut.double_click=dbl;force dut.click_x=cx;force dut.click_y=cy;
        force dut.u_audio.pluck_valid=pluck;
        wait(rst);repeat(20)@(negedge clk);
        tap(340,150);tap(100,110);
        if(dut.page!=2)$fatal(1,"FAIL: removed slow practice remained selectable");
        tap(100,240);
        if(dut.page!=2)$fatal(1,"FAIL: unimported fifth slot exposed");
        one={16'd0,16'hbeef,8'd0,8'd2,8'd0,8'd79,32'd128,32'd0};
        two={16'd0,16'h1234,8'd0,8'd2,8'd1,8'd50,32'd128,32'd12000};
        song_crc=crc_record(crc_record(32'hffffffff,one),two)^32'hffffffff;
        transact(1,123,0,0,0);
        transact(3,123,1,{32'd0,song_crc,32'd13024,16'd2,8'd1,8'd4},0);
        tap(100,70);if(dut.page!=2)$fatal(1,"FAIL: touch bypassed import lock");
        transact(4,123,2,one,0);transact(4,123,3,two,0);transact(5,123,4,0,0);
        if(dut.audio_catalog_valid!=16 || dut.system_catalog_valid!=16 || dut.audio_catalog_data!==dut.system_catalog_data)
            $fatal(1,"FAIL: production catalog publication");
        tap(100,240);if(dut.page!=3 || dut.selected_slot!=4)$fatal(1,"FAIL: imported fifth slot not touch selectable");
        tap(340,220);wait(!dut.transition && dut.page>=4);
        if(dut.timbre_mode!=1)$fatal(1,"FAIL: actual recommended timbre not loaded");
        // While playing, no import can reserve writable space or alter audio.
        transact(3,123,5,{32'd0,song_crc,32'd13024,16'd2,8'd1,8'd4},1);
        wait(game_time>=6000);
        if(dut.u_display.u_ui.progress_step!=28 || dut.u_display.u_ui.progress_pixels<100)
            $fatal(1,"FAIL: runtime duration not used for progress");
        wait(dut.page==6);
        if(attacks!=2 || nonzero<1000 || dut.audio_game_snapshot[127:96]!=0 || dut.display_fault)
            $fatal(1,"FAIL: imported complete preview attacks%0d nonzero%0d score%0d",attacks,nonzero,dut.audio_game_snapshot[127:96]);
        // Preview must not score. Now replay with two actual pluck-control
        // pulses at the declared ADC-event stimulus boundary and score them.
        tap(80,230);if(dut.page!=3)$fatal(1,"FAIL: replay ready page");
        tap(100,220);wait(dut.page==5);
        wait(game_time>=100);@(negedge ac);pluck=1;@(negedge ac);pluck=0;
        wait(game_time>=12100);@(negedge ac);pluck=2;@(negedge ac);pluck=0;
        wait(dut.page==6);
        if(attacks!=4 || dut.audio_game_snapshot[127:96]!=200 || dut.display_fault)
            $fatal(1,"FAIL: imported player hits/score attacks%0d score%0d",attacks,dut.audio_game_snapshot[127:96]);
        tap(220,230);if(dut.page!=2)$fatal(1,"FAIL: return to songs");
        tap(100,70);if(dut.page!=3 || dut.selected_slot!=0)$fatal(1,"FAIL: builtin song selection regressed");
        $display("PASS: production top UART -> DPB -> frame-atomic dual-clock directory -> fifth touch slot -> actual second timbre -> G5/D3 preview + player hits/200 score/result/progress, BUSY and touch lock; %0d samples %0d frames; touch/ADC-event stimulus boundaries and UART-divider/countdown acceleration stated",samples,frames);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: P3 production top watchdog page%0d service%0d",dut.page,dut.p3.service.protocol.state);end
endmodule
