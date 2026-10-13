`timescale 1ns/1ps
// Real 48 kHz / 12.288 MHz FULL audio, telemetry CDC and 50 MHz LCD scan.
// Only the bench's note timeout is shortened; all 32 modes/ROMs are intact.
module tb_guitar_radial_fade_integration;
    reg audio_clk=0,clk=0,rst_n=0,stable=0;
    always #40.690104 audio_clk=~audio_clk;
    always #10 clk=~clk;
    reg [15:0] fret=16'h7531;
    reg [3:0] pluck=0;
    wire tick,pcm_valid,voice_valid;
    wire signed [23:0] pcm;
    wire [95:0] voices;
    wire [3:0] active,attack;
    wire [127:0] increment;
    wire [399:0] snapshot;
    wire pclk,hs,vs,de,bl;
    wire [5:0] r,g,b;
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) audio(
        .clk_audio_ref(audio_clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(fret),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(1'b0),.rock_select(1'b0),
        .sustain_enable(1'b0),.chorus_enable(1'b0),.reverb_enable(1'b0),.harmony_enable(1'b0),
        .sample_tick(tick),.pcm_mix_valid(pcm_valid),.pcm_mix(pcm),.voice_active(active),.voice_pcm(voices),
        .dac_bclk(),.dac_lrck(),.dac_din(),.display_phase_inc(increment),
        .display_note_on(attack),.display_voice_sample_valid(voice_valid),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );
    defparam audio.g_piano.u_core.voice[0].u_voice.MAX_SAMPLES=4096;
    defparam audio.g_piano.u_core.voice[1].u_voice.MAX_SAMPLES=4096;
    defparam audio.g_piano.u_core.voice[2].u_voice.MAX_SAMPLES=4096;
    defparam audio.g_piano.u_core.voice[3].u_voice.MAX_SAMPLES=4096;
    guitar_visual_telemetry #(.HOLD_INACTIVE_PITCH(1)) telemetry(.clk(audio_clk),.rst_n(rst_n),
        .sample_tick(tick),.voice_sample_valid(voice_valid),.phase_inc(increment),
        .note_on(attack),.voice_active(active),.fret_id(fret),.voice_pcm(voices),.snapshot(snapshot));
    guitar_radial_display display(.audio_clk(audio_clk),.audio_rst_n(rst_n),.clk(clk),.rst_n(rst_n),
        .audio_snapshot(snapshot),.audio_pcm_valid(pcm_valid),.audio_pcm(pcm),
        .lcd_pclk(pclk),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_de(de),.lcd_backlight(bl),
        .lcd_r(r),.lcd_g(g),.lcd_b(b));
    always @(posedge clk)if(rst_n && display.initialized)begin
        if(display.pcm_overrun || display.renderer_deadline_miss)$fatal(1,"FAIL: fade integration misses PCM/row deadline");
    end
    integer captures=0,last_bright=0;
    reg [31:0] frame_gain;
    task automatic capture(input string name);
        integer i,h,v,f,visible,bright;
        begin
            @(negedge vs);
            repeat(60)@(negedge clk); // mailbox settles during vertical blank
            frame_gain=display.u_palette.curve_gain;
            f=$fopen(name,"w");if(!f)$fatal(1,"FAIL: frame output");
            $fwrite(f,"P3\n480 272\n255\n");visible=0;bright=0;
            // Start at the first active pixel; count all 272 complete rows.
            wait(de);@(posedge pclk);#1;
            while(visible<130560)begin
                if(de)begin
                    if(display.u_palette.curve_gain!==frame_gain)$fatal(1,"FAIL: brightness tears inside visible frame");
                    h=visible%480;v=visible/480;
                    if(h>=269 && h<=418 && v>=61 && v<=210 &&
                       int'(r)+int'(g)+int'(b)>25)bright++;
                    if($isunknown({r,g,b}))$fatal(1,"FAIL: unknown fade pixel");
                    $fwrite(f,"%0d %0d %0d\n",r*4,g*4,b*4);visible++;
                end
                if(visible<130560)begin @(posedge pclk);#1;end
            end
            $fclose(f);captures++;last_bright=bright;
            $display("PASS: fade captured %s active=%b gain=%h bright_curve_pixels=%0d",name,
                display.display_active,frame_gain,bright);
        end
    endtask
    integer i,j;
    reg [127:0] held_pitch;
    reg [31:0] previous_gain;
    initial begin
        #1000;rst_n=1;
        @(negedge audio_clk);stable=1;@(negedge audio_clk);stable=0;
        #24000000;
        @(negedge audio_clk);pluck=15;@(negedge audio_clk);pluck=0;
        wait(active==15);
        capture("radial_fade_attack.ppm");
        if(frame_gain!=32'hffffffff || last_bright<100)$fatal(1,"FAIL: four curves did not attack");
        wait(active==0);held_pitch=snapshot[255:128];
        // Selecting a new fret after natural expiration prepares the next
        // note but the visual tails must continue at the previous pitches.
        @(negedge audio_clk);fret=16'h8888;stable=1;@(negedge audio_clk);stable=0;
        previous_gain=32'hffffffff;
        for(i=0;i<8;i++)begin
            capture($sformatf("radial_fade_tail_%0d.ppm",i));
            for(j=0;j<4;j++)if(frame_gain[j*8+:8]>previous_gain[j*8+:8])
                $fatal(1,"FAIL: natural-expiration tail brightness increased");
            if(snapshot[255:128]!=held_pitch || active!=0 || audio.note_off!=0)
                $fatal(1,"FAIL: display tail changed silent pitch/audio control");
            previous_gain=frame_gain;
        end
        if(frame_gain!=0 || display.curve_active!=0 || last_bright!=0)
            $fatal(1,"FAIL: expired curves do not return to the original background");
        @(negedge audio_clk);pluck=1;@(negedge audio_clk);pluck=0;
        capture("radial_fade_retrigger.ppm");
        if(frame_gain[7:0]!=255 || frame_gain[31:8]!=0 || display.curve_active!=1)
            $fatal(1,"FAIL: single-string retrigger revives expired neighbors");
        if(captures!=10)$fatal(1,"FAIL: missing fade frames");
        $display("PASS: FULL four-voice natural expiration, last-pitch tail, eight gradual LCD frames, frame-stable RGB, exact background and isolated retrigger; 32 modes and all audio ROMs intact (bench timeout only shortened)");
        $finish;
    end
    initial begin #600000000;$fatal(1,"FAIL: fade integration timeout");end
endmodule
