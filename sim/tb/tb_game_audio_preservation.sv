`timescale 1ns/1ps
module tb_game_audio_preservation;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable_valid=0,command_valid=0,compare_audio=1;
    reg [1:0] command_mode=1;
    reg [15:0] frets=0;reg [3:0] pluck=0;reg [7:0] velocity=8'he4;
    reg timbre=0,rock=0,chorus=0,sustain=0,harmony=0,room=0;
    wire tick,tick_accepted,tick_default,ack,switching;
    wire [1:0] mode;
    wire [3:0] active,on,off,forced;
    wire [127:0] phase,target;
    wire [7:0] routed_velocity;
    wire [255:0] snapshot;
    audio_mode_router router(.clk(clk),.rst_n(rst_n),.sample_tick(tick),.command_valid(command_valid),
        .command_mode(command_mode),.command_ack(ack),.mode(mode),.switching(switching),
        .stable_valid(stable_valid),.fret_id(frets),.pluck_valid(pluck),.velocity(velocity),
        .voice_active(active),.audible_phase(phase),.note_on(on),.note_off(off),.force_release(forced),
        .target_phase(target),.note_velocity(routed_velocity),.game_snapshot(snapshot));
    `define CHAIN_PARAMS .USE_PIANO(1),.PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1),.I2S_ENABLE(1)
    `define COMMON_PORTS .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable_valid),.stable_fret_id(frets),.pluck_valid(pluck), \
        .timbre_select(timbre),.rock_select(rock),.chorus_enable(chorus),.sustain_enable(sustain), \
        .harmony_enable(harmony),.reverb_enable(room),.pcm_mix_valid(),.pcm_mix(),.voice_pcm(), \
        .display_note_on(),.display_voice_sample_valid(),.dac_bclk(),.dac_lrck(),.dac_din(),.i2s_bclk(),.i2s_ws(),.i2s_data()
    accepted_four_string_board_audio_chain #(`CHAIN_PARAMS) accepted(
        `COMMON_PORTS,.velocity_level(velocity),.sample_tick(tick_accepted),.voice_active(),.display_phase_inc());
    four_string_board_audio_chain #(`CHAIN_PARAMS) default_chain(
        `COMMON_PORTS,.velocity_level(velocity),.sample_tick(tick_default),.voice_active(),.display_phase_inc(),
        .external_note_on(4'd0),.external_note_off(4'd0),.external_force_release(4'd0),.external_phase_inc(128'd0));
    four_string_board_audio_chain #(`CHAIN_PARAMS,.EXTERNAL_CONTROL_ENABLE(1)) routed(
        `COMMON_PORTS,.velocity_level(routed_velocity),.sample_tick(tick),.voice_active(active),.display_phase_inc(phase),
        .external_note_on(on),.external_note_off(off),.external_force_release(forced),.external_phase_inc(target));
    integer samples=0,compared_cycles=0,exit_sample;
    always @(negedge clk)if(rst_n)begin
        if(tick)samples=samples+1;
        if(compare_audio)begin
            compared_cycles=compared_cycles+1;
            if({tick,default_chain.stereo_valid,routed.stereo_valid}!=={tick_accepted,accepted.stereo_valid,accepted.stereo_valid} ||
               default_chain.voice_pcm!==accepted.voice_pcm || routed.voice_pcm!==accepted.voice_pcm ||
               {default_chain.pcm16_left_out,default_chain.pcm16_right_out}!=={accepted.pcm16_left_out,accepted.pcm16_right_out} ||
               {routed.pcm16_left_out,routed.pcm16_right_out}!=={accepted.pcm16_left_out,accepted.pcm16_right_out} ||
               {default_chain.dac_bclk,default_chain.dac_lrck,default_chain.dac_din}!=={accepted.dac_bclk,accepted.dac_lrck,accepted.dac_din} ||
               {routed.i2s_bclk,routed.i2s_ws,routed.i2s_data}!=={accepted.i2s_bclk,accepted.i2s_ws,accepted.i2s_data})
                $fatal(1,"FAIL: accepted/default/routed performance audio diverged sample=%0d",samples);
        end
        if(|routed.deadline_miss)$fatal(1,"FAIL: full synthesis missed 256-cycle budget");
    end
    task strike(input [3:0] mask);
        @(negedge clk);pluck=mask;@(negedge clk);pluck=0;
    endtask
    task fret(input [15:0] value);
        @(negedge clk);frets=value;stable_valid=1;@(negedge clk);stable_valid=0;
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;command_valid=1;wait(ack);
        @(negedge clk);command_valid=0;
        wait(samples==20);fret(16'h2341);strike(15);
        wait(samples==800);fret(0); // Accepted release-to-open slide.
        wait(samples==1200);chorus=1;room=1;strike(5);
        wait(samples==2200);timbre=1;strike(15);
        wait(samples==3300);harmony=1;sustain=1;strike(10);
        wait(samples==4400);timbre=0;rock=1;strike(15);
        wait(samples==6000);chorus=0;room=0;harmony=0;strike(15);
        wait(samples==8192);@(negedge clk);compare_audio=0;exit_sample=samples;
        command_mode=0;command_valid=1;wait(ack);
        if(mode!=0 || active!=0 || samples-exit_sample>1920)
            $fatal(1,"FAIL: sustain-independent exit did not finish inside 40 ms");
        @(negedge clk);command_valid=0;
        $display("PASS: %0d cycles / 8192 samples identical to accepted master, all timbres/FX; sustain exit %0d samples",
            compared_cycles,samples-exit_sample);$finish;
    end
    initial begin #40000000;$fatal(1,"FAIL: audio/exit watchdog samples=%0d active=%b",samples,active);end
endmodule
