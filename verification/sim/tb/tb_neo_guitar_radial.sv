`timescale 1ns/1ps
module tb_neo_guitar_radial;
    reg audio_clk=0,sys_clk=0;
    always #40.690104 audio_clk=~audio_clk;
    always #10 sys_clk=~sys_clk;
    reg [31:0] pressed=0;
    reg [11:0] adc_code[0:3];
    reg key1=1,key2=1,key3=1;
    tri [3:0] rows,ref_rows;
    wire [7:0] cols=(rows[0]===0) ? ~pressed[7:0] : (rows[1]===0) ? ~pressed[15:8] :
                         (rows[2]===0) ? ~pressed[23:16] : (rows[3]===0) ? ~pressed[31:24] : 8'hff;
    wire [7:0] ref_cols=(ref_rows[0]===0) ? ~pressed[7:0] : (ref_rows[1]===0) ? ~pressed[15:8] :
                         (ref_rows[2]===0) ? ~pressed[23:16] : (ref_rows[3]===0) ? ~pressed[31:24] : 8'hff;
    wire cs,sclk,mosi,bclk,lrck,din,pa;
    wire ref_cs,ref_sclk,ref_mosi,ref_bclk,ref_lrck,ref_din,ref_pa;
    wire [3:0] leds,ref_leds;
    reg miso=0;
    wire pclk,hs,vs,de,bl;
    wire [5:0] r,g,b;
    neo_guitar_radial_top #(.KEY_DEBOUNCE_CYCLES(8),.KEY_LONG_PRESS_CYCLES(512),
        .MATRIX_CLK_DIV(2),.MATRIX_SETTLE_CYCLES(2),.MATRIX_DEBOUNCE_FRAMES(2),
        .ADC_SPI_CLK_DIV(2),.PLUCK_DEAD_SAMPLES(4),.PLUCK_SETTLE_SAMPLES(2)) dut(
        .audio_clk_12m288(audio_clk),.sys_clk_50m(sys_clk),
        .USER_BUTTON1_n(key1),.USER_BUTTON2_n(key2),.USER_BUTTON3_n(key3),
        .ROW0(rows[0]),
        .ROW1(rows[1]),
        .ROW2(rows[2]),
        .ROW3(rows[3]),
        .COL0(cols[0]),
        .COL1(cols[1]),
        .COL2(cols[2]),
        .COL3(cols[3]),
        .COL4(cols[4]),
        .COL5(cols[5]),
        .COL6(cols[6]),
        .COL7(cols[7]),
        .adc_cs_n(cs),.adc_sclk(sclk),.adc_mosi(mosi),.adc_miso(miso),
        .dac_bclk(bclk),.dac_lrck(lrck),.dac_din(din),.pa_en_n(pa),.event_led(leds),
        .lcd_pclk(pclk),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_de(de),.lcd_backlight(bl),.lcd_r(r),.lcd_g(g),.lcd_b(b));
    neo_guitar_audio_full_top #(.KEY_DEBOUNCE_CYCLES(8),.KEY_LONG_PRESS_CYCLES(512),
        .MATRIX_CLK_DIV(2),.MATRIX_SETTLE_CYCLES(2),.MATRIX_DEBOUNCE_FRAMES(2),
        .ADC_SPI_CLK_DIV(2),.PLUCK_DEAD_SAMPLES(4),.PLUCK_SETTLE_SAMPLES(2)) baseline(
        .audio_clk_12m288(audio_clk),
        .USER_BUTTON1_n(key1),.USER_BUTTON2_n(key2),.USER_BUTTON3_n(key3),
        .ROW0(ref_rows[0]),
        .ROW1(ref_rows[1]),
        .ROW2(ref_rows[2]),
        .ROW3(ref_rows[3]),
        .COL0(ref_cols[0]),
        .COL1(ref_cols[1]),
        .COL2(ref_cols[2]),
        .COL3(ref_cols[3]),
        .COL4(ref_cols[4]),
        .COL5(ref_cols[5]),
        .COL6(ref_cols[6]),
        .COL7(ref_cols[7]),
        .adc_cs_n(ref_cs),.adc_sclk(ref_sclk),.adc_mosi(ref_mosi),.adc_miso(miso),
        .dac_bclk(ref_bclk),.dac_lrck(ref_lrck),.dac_din(ref_din),.pa_en_n(ref_pa),.event_led(ref_leds));

    integer rises=0,channel=0;
    reg [4:0] command=0;
    reg [11:0] conversion=0;
    always @(negedge cs) begin rises=0;command=0;miso=0;end
    always @(posedge sclk) if(!cs) begin
        rises++;
        if(rises<=5) command={command[3:0],mosi};
        if(rises==5) begin channel=command[2:0];conversion=adc_code[channel];end
    end
    always @(negedge sclk) if(!cs)
        miso=(rises>=7 && rises<=18) ? conversion[18-rises] : 1'b0;
    integer compared=0,nonzero_pcm=0;
    always @(posedge audio_clk) begin
        #1;
        if({rows,cs,sclk,mosi,bclk,lrck,din,pa,leds} !==
           {ref_rows,ref_cs,ref_sclk,ref_mosi,ref_bclk,ref_lrck,ref_din,ref_pa,ref_leds})
            $fatal(1,"FAIL: integrated physical audio interface differs from FULL baseline");
        if(dut.audio_rst_n) begin
            compared++;
            if(dut.u_audio.u_board_audio_chain.phase_inc !== baseline.u_audio.u_board_audio_chain.phase_inc ||
               dut.u_audio.u_board_audio_chain.voice_pcm !== baseline.u_audio.u_board_audio_chain.voice_pcm ||
               dut.visual_active !== baseline.u_audio.audio_voice_active)
                $fatal(1,"FAIL: fundamental/lifecycle/32-mode per-voice PCM differs");
            if(dut.visual_pcm_valid && dut.visual_pcm!=0) nonzero_pcm++;
            if(dut.u_audio.u_board_audio_chain.g_piano.u_core.deadline_miss!=0)
                $fatal(1,"FAIL: audio computation missed sample deadline");
        end
    end
    time last_change=0;
    always @(r or g or b or hs or vs or de) last_change=$time;
    reg old_bank=0;
    always @(posedge sys_clk) begin
        #1;
        if(dut.lcd_rst_n && dut.u_display.initialized) begin
            if(dut.u_display.pcm_overrun)$fatal(1,"FAIL: PCM mailbox overrun");
            if(dut.u_display.renderer_deadline_miss)
                $fatal(1,"FAIL: scanline deadline state=%0d row=%0d scan=%0d,%0d",dut.u_display.u_renderer.state,
                    dut.u_display.u_renderer.row_y,dut.u_display.u_scan.h_count,dut.u_display.u_scan.v_count);
            if(dut.u_display.u_renderer.front_bank!=old_bank && de)
                $fatal(1,"FAIL: visual bank swapped in active picture");
            old_bank=dut.u_display.u_renderer.front_bank;
        end else old_bank=0;
    end
    task automatic capture(input string name);
        integer i,h,v,f,visible;
        reg expected_de;
        time previous;
        begin
            @(negedge vs);@(posedge pclk);#1;
            f=$fopen(name,"w");if(!f) $fatal(1,"FAIL: capture output");
            $fwrite(f,"P3\n480 272\n255\n");visible=0;previous=0;
            for(i=0;i<531*292;i++) begin
                if(i!=0) begin @(posedge pclk);#1;end
                h=i%531;v=i/531;
                if(previous!=0 && $time-previous!=120) $fatal(1,"FAIL: integrated pixel clock");
                previous=$time;
                if($isunknown({de,hs,vs,r,g,b})) $fatal(1,"FAIL: unknown integrated panel output");
                expected_de=h>=43 && h<523 && v>=12 && v<284;
                if(de!==expected_de || hs!==(h>=4) || vs!==(v>=4)) $fatal(1,"FAIL: integrated panel geometry");
                if($time-last_change<60) $fatal(1,"FAIL: integrated RGB settling");
                if(de) begin visible++;$fwrite(f,"%0d %0d %0d\n",r*4,g*4,b*4);end
                else if({r,g,b}!=0) $fatal(1,"FAIL: integrated blanking");
            end
            $fclose(f);
            if(visible!=130560) $fatal(1,"FAIL: integrated visible pixel count");
            $display("PASS: integrated captured %s active=%b hz=%h fret=%h",name,
                dut.u_display.display_active,dut.u_display.hz,dut.u_display.fret);
        end
    endtask
    task automatic pluck_all;
        integer channel_index;
        begin
            for(channel_index=0;channel_index<4;channel_index++) adc_code[channel_index]=2753;
            #150000;
            for(channel_index=0;channel_index<4;channel_index++) adc_code[channel_index]=2053;
        end
    endtask
    task automatic press_key(input integer which,clocks);
        begin
            @(negedge audio_clk);
            case(which) 1:key1=0;2:key2=0;3:key3=0;endcase
            repeat(clocks) @(negedge audio_clk);
            key1=1;key2=1;key3=1;
            repeat(30) @(negedge audio_clk);
        end
    endtask
    integer i,fft_frames=0;
    always @(posedge sys_clk)if(dut.u_display.fft_done)fft_frames++;
    initial begin
        for(i=0;i<4;i++) adc_code[i]=2053;
        #200000;pressed=32'h40100401;
        #20000000;
        if(dut.visual_fret!=16'h7531 || dut.visual_active!=0 || dut.u_display.display_active!=0)
            $fatal(1,"FAIL: frets without pluck start voices/curves");
        for(i=0;i<4;i++) adc_code[i]=2753;
        #150000;
        for(i=0;i<4;i++) adc_code[i]=2053;
        wait(dut.visual_active==15);
        #20000000; // The double-buffered view publishes on the following frame.
        capture("radial_four_voices.ppm");
        if(dut.u_display.display_active!=15) $fatal(1,"FAIL: four voices not displayed");
        if(dut.u_display.hz[10:0]!=349 || dut.u_display.hz[21:11]!=294 ||
           dut.u_display.hz[32:22]!=262 || dut.u_display.hz[43:33]!=220)
            $fatal(1,"FAIL: actual fret frequencies not shown");
        press_key(1,40);#8000000; // Bright string, same 32 modes.
        if(dut.timbre_mode!=1) $fatal(1,"FAIL: retained bright timbre");
        pluck_all();
        press_key(1,40);#8000000; // Wah V4, same 32 modes/long decay.
        if(dut.timbre_mode!=2) $fatal(1,"FAIL: retained wah timbre");
        pluck_all();
        press_key(2,40);press_key(3,40);
        press_key(2,800);#8000000;
        if(!dut.chorus_enable || !dut.sustain_enable || !dut.harmony_enable)
            $fatal(1,"FAIL: retained chorus/sustain/long-press harmony");
        pluck_all();#1000000;
        if(!dut.u_audio.u_board_audio_chain.g_piano.u_core.voice[0].u_voice.harmony_latched)
            $fatal(1,"FAIL: fifth harmony did not latch on real pluck");
        // The 20 ms slide plus frame snapshot/double-buffer publication can
        // span two refreshes; inspect the stable C5 frame after both settle.
        pressed[7:0]=8'h80;#45000000;
        if(dut.visual_phase_inc[31:0]!=32'h02CA6987) $fatal(1,"FAIL: actual slide pitch");
        capture("radial_slide_c5.ppm");
        if(dut.u_display.hz[10:0]!=523 || dut.u_display.fret[3:0]!=8)
            $fatal(1,"FAIL: display did not follow audible slide and selected fret");
        pressed[7:0]=0;#30000;
        #40000000;
        if(!dut.visual_active[0] || dut.visual_phase_inc[31:0]!=32'h01C20D2F)
            $fatal(1,"FAIL: release must continue its natural envelope at open E4");
        if(dut.u_audio.u_board_audio_chain.note_off!=0)
            $fatal(1,"FAIL: fret release still damps the voice");
        // Disabling sustain restores natural decay, not fret damping.
        press_key(3,40);
        if(!dut.reverb_enable || dut.sustain_enable) $fatal(1,"FAIL: retained reverb control");
        #40000000;
        capture("radial_release.ppm");
        if(!dut.visual_active[0] || !dut.u_display.display_active[0] ||
           dut.u_display.hz[10:0]!=330 || dut.u_display.fret[3:0]!=0)
            $fatal(1,"FAIL: open-string continuation is not audible/visible");
        // Reverb control and return to piano are also compared sample-for-sample.
        press_key(1,40);#8000000;
        if(dut.timbre_mode!=0 || !dut.reverb_enable) $fatal(1,"FAIL: retained piano/reverb control");
        #300000000; // Full audio/spectrum comparison during natural decay.
        if(nonzero_pcm<100 || compared<100000) $fatal(1,"FAIL: insufficient audible baseline comparison");
        if(fft_frames<15)$fatal(1,"FAIL: spectrum stopped");
        $display("PASS: radial FFT windows %0d, no PCM loss or row misses",fft_frames);
        $display("PASS: integrated four-fret/four-pluck, slide/release, all three 32-mode timbres, effects and harmony; %0d audio clocks EXACTLY match FULL baseline, nonzero samples=%0d",compared,nonzero_pcm);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: integration timeout");end
endmodule
