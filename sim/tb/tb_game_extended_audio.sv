`timescale 1ns/1ps
`include "guitar_config.vh"
module tb_game_extended_audio;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #40.690104 clk=~clk;
    reg rst=0,timbre=0,rock=0;
    reg [3:0] on=0,off=0,release_all=0;
    reg [127:0] phase=0;
    wire tick_a,tick_b,valid_a,valid_b;
    wire signed [23:0] pcm_a,pcm_b;
    wire [127:0] audible_a,audible_b;
    wire [3:0] active_a,active_b;
    wire [5:0] pins_a,pins_b;
`define ARGS .clk_audio_ref(clk),.rst_n(rst),.stable_valid(1'b0),.stable_fret_id(16'd0), \
    .pluck_valid(4'd0),.velocity_level(8'haa),.timbre_select(timbre),.rock_select(rock), \
    .chorus_enable(1'b1),.sustain_enable(1'b1),.harmony_enable(1'b1),.reverb_enable(1'b1), \
    .voice_pcm(),.display_note_on(),.display_voice_sample_valid(), \
    .external_note_on(on),.external_note_off(off),.external_force_release(release_all), \
    .external_phase_inc(phase),.game_cue_enable(1'b0),.game_miss_event(1'b0)
`define OUTS(x) .sample_tick(tick_``x),.pcm_mix_valid(valid_``x),.pcm_mix(pcm_``x), \
    .voice_active(active_``x),.display_phase_inc(audible_``x), \
    .dac_bclk(pins_``x[0]),.dac_lrck(pins_``x[1]),.dac_din(pins_``x[2]), \
    .i2s_bclk(pins_``x[3]),.i2s_ws(pins_``x[4]),.i2s_data(pins_``x[5])
    four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.I2S_ENABLE(1),.USE_PIANO(1),
        .PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1),.CONTROL_PHASE_VALUE_BITS(27)) dut(.control_pipeline_idle(),.control_timbre_busy(),`ARGS,`OUTS(a));
    four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.I2S_ENABLE(1),.USE_PIANO(1),
        .PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1),.CONTROL_PHASE_VALUE_BITS(32)) full32(.control_pipeline_idle(),.control_timbre_busy(),`ARGS,`OUTS(b));
`undef ARGS
`undef OUTS
    function automatic [31:0] increment(input integer midi);
        real hz;
        begin hz=440.0*(2.0**((midi-69)/12.0));increment=$rtoi(hz*4294967296.0/48000.0+0.5);end
    endfunction
    integer cycles=0,samples=0,nonzero=0,mode;
    always @(posedge clk)begin
        #1;
        if(rst)begin
            cycles=cycles+1;
            if({tick_a,valid_a,pcm_a,audible_a,active_a,pins_a}!=={tick_b,valid_b,pcm_b,audible_b,active_b,pins_b})
                $fatal(1,"FAIL: 27-bit chain differs from full32 arithmetic sample=%0d phase=%h/%h PCM=%h/%h",samples,audible_a,audible_b,pcm_a,pcm_b);
            if(dut.deadline_miss!==0 || full32.deadline_miss!==0)$fatal(1,"FAIL: extended polyphony audio deadline");
            if(valid_a)begin samples=samples+1;if(pcm_a!=0)nonzero=nonzero+1;end
        end
    end
    task pulse(input bit attack,input bit stop);
        @(negedge clk);while(!tick_a)@(negedge clk);
        on=attack ? 15 : 0;release_all=stop ? 15 : 0;
        @(negedge clk);on=0;release_all=0;
    endtask
    task wait_samples(input integer count);
        integer goal;
        begin goal=samples+count;wait(samples>=goal);@(negedge clk);end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst=1;
        for(mode=0;mode<3;mode=mode+1)begin
            timbre=mode==1;rock=mode==2;
            phase={increment(50),increment(72),increment(78),increment(79)};
            pulse(1,0);wait_samples(128);
            if(audible_a[31:0]!==increment(79) || !audible_a[26])$fatal(1,"FAIL: held G5 folded after attack");
            // Active-voice slides in both directions must retain all 27 bits.
            phase[31:0]=increment(50);wait_samples(1100);
            if(audible_a[31:0]!==increment(50))$fatal(1,"FAIL: extended down-slide endpoint");
            phase[31:0]=increment(79);wait_samples(1100);
            if(audible_a[31:0]!==increment(79))$fatal(1,"FAIL: extended up-slide endpoint");
        end
        pulse(0,1);wait_samples(2048);
        if(active_a || nonzero==0)$fatal(1,"FAIL: extended force release/silent audio");
        $display("PASS: extended D3-G5 four-voice chain equals full32 oracle for %0d clocks/%0d samples, three timbres/all FX, G5 held bit26, bidirectional slides, sustained force release, PT8211/I2S and zero deadlines",cycles,samples);
        $finish;
    end
    initial begin #300000000;$fatal(1,"FAIL: extended audio timeout");end
endmodule
