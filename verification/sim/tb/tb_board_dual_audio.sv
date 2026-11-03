`timescale 1ns/1ps
// Before/after full audio chain, including all timbres and stereo effects.
// Standard I2S is independently decoded and compared to actual PT8211 words.
module tb_board_dual_audio;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable=0,timbre=0,rock=0,chorus=0,sustain=0,harmony=0,room=0;
    reg [15:0] frets=16'h5553;
    reg [3:0] pluck=0;
    reg [7:0] velocity=8'haa;
    wire pb,pl,pd,ob,ol,od,ib,iw,id;
    wire [1:0] ticks,pcm_valid;
    wire [47:0] pcm;
    wire [191:0] voices;
    wire [7:0] active;
    pre_i2s_four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) before_change(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(velocity),.timbre_select(timbre),.rock_select(rock),
        .chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(harmony),.reverb_enable(room),
        .sample_tick(ticks[0]),.pcm_mix_valid(pcm_valid[0]),.pcm_mix(pcm[23:0]),
        .voice_active(active[3:0]),.voice_pcm(voices[95:0]),.dac_bclk(ob),.dac_lrck(ol),.dac_din(od),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid());
    four_string_board_audio_chain #(.I2S_ENABLE(1),.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) dut(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(velocity),.timbre_select(timbre),.rock_select(rock),
        .chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(harmony),.reverb_enable(room),
        .sample_tick(ticks[1]),.pcm_mix_valid(pcm_valid[1]),.pcm_mix(pcm[47:24]),
        .voice_active(active[7:4]),.voice_pcm(voices[191:96]),.dac_bclk(pb),.dac_lrck(pl),.dac_din(pd),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid(),
        .i2s_bclk(ib),.i2s_ws(iw),.i2s_data(id));
    integer checked=0,frames=0,i2s_frames=0,nonzero=0,pcm_frames=0,last_pcm_clock=0;
    reg [31:0] pt_words[0:16383];
    reg [31:0] pt_rx=0;
    integer pt_bits=0;
    always @(posedge clk)begin
        #2;
        if(rst_n)begin
            checked++;
            if({pb,pl,pd,ticks[1],pcm_valid[1],active[7:4]}!==
               {ob,ol,od,ticks[0],pcm_valid[0],active[3:0]})$fatal(1,"FAIL: old path control/DAC changed");
            if(voices[191:96]!==voices[95:0] || pcm[47:24]!==pcm[23:0] ||
               dut.pcm16_left_out!==before_change.pcm16_left_out ||
               dut.pcm16_right_out!==before_change.pcm16_right_out)
                $fatal(1,"FAIL: original PCM/tone/effects changed");
            if(dut.deadline_miss!=0)$fatal(1,"FAIL: synthesis deadline");
            if(dut.pcm16_left_valid)begin
                if(!dut.pcm16_right_valid)$fatal(1,"FAIL: stereo valid");
                if(last_pcm_clock && checked-last_pcm_clock!=256)$fatal(1,"FAIL: PCM sample lost or duplicated");
                last_pcm_clock=checked;
                pcm_frames++;
            end
        end
    end
    always @(posedge pb)if(rst_n)begin
        #1;pt_rx={pt_rx[30:0],pd};pt_bits++;
        if(pt_bits==32)begin
            pt_words[frames]=pt_rx;frames++;pt_bits=0;
            if(pt_rx!=0)nonzero++;
        end
    end
    reg locked=0,last_ws=1,channel=0;
    reg [31:0] rx=0,left_word=0;
    integer bits=0;
    always @(posedge ib)if(rst_n)begin
        #1;
        if(locked)begin
            rx={rx[30:0],id};bits++;
            if(bits==32)begin
                if(rx[15:0]!==0)$fatal(1,"FAIL: I2S padding");
                if(!channel)left_word=rx;
                else begin
                    if(frames<=i2s_frames || {left_word[31:16],rx[31:16]}!==pt_words[i2s_frames])
                        $fatal(1,"FAIL: I2S vs PT8211 at stereo frame %0d",i2s_frames);
                    i2s_frames++;
                end
            end
        end
        if(iw!==last_ws)begin
            if(locked && bits!=32)$fatal(1,"FAIL: I2S slot length");
            locked=1;channel=iw;bits=0;rx=0;last_ws=iw;
        end
    end
    task strike(input [3:0] mask);
        @(negedge clk);pluck=mask;@(negedge clk);pluck=0;
    endtask
    task pitch(input [15:0] fret);
        @(negedge clk);frets=fret;stable=1;@(negedge clk);stable=0;
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;pitch(16'h5553);strike(15);
        wait(frames>=1200);pitch(0); // Accepted open-string release/decay.
        wait(frames>=2400);chorus=1;room=1;harmony=1;strike(15);
        wait(frames>=3600);sustain=1;timbre=1;strike(7);
        wait(frames>=4800);timbre=0;rock=1;velocity=8'hff;pitch(16'h3333);strike(15);
        wait(frames>=6000);pitch(0);sustain=0;
        wait(frames>=7200);rock=0;chorus=0;room=0;harmony=0;strike(3);
        wait(i2s_frames>=8192);
        // The first serial frame is power-on silence while the first PCM
        // traverses the existing synthesis/effects pipeline.
        if(nonzero<7000 || pcm_frames<8191)
            $fatal(1,"FAIL: insufficient audible coverage: nonzero=%0d PCM=%0d",nonzero,pcm_frames);
        $display("PASS: complete original audio PCM/PT8211 unchanged for %0d reference clocks; %0d decoded I2S pairs exactly match PT8211; %0d nonzero; piano/bright/wah, chorus, room, harmony, sustain, release/restrike",checked,i2s_frames,nonzero);
        $finish;
    end
    initial begin #24000000;$fatal(1,"FAIL: dual audio timeout");end
endmodule
