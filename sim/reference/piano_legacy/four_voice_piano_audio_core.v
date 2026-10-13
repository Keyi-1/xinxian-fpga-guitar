`include "guitar_config.vh"
module legacy_four_voice_piano_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer HAMMER_ENABLE = 1,
    parameter integer MODES = 8,
    parameter integer CONTROL_ENABLE = 0,
    parameter integer ROCK_ENABLE = 0
) (
    input wire clk_audio_ref, rst_n,
    input wire [3:0] note_on, note_off,
    input wire [7:0] velocity_level,
    input wire [127:0] phase_inc,
    input wire timbre_select, rock_select, sustain_enable, harmony_enable,
    output wire sample_tick, sample_valid,
    output wire [3:0] voice_active,
    output wire [95:0] voice_pcm,
    output wire [7:0] voice_profile,
    output wire [3:0] deadline_miss,
    output wire [8:0] timbre_blend,
    output wire [8:0] rock_blend,
    output wire timbre_busy
);
    reg [3:0] pending_on, pending_off;
    wire bright_busy,rock_busy;
    assign timbre_busy=bright_busy|rock_busy;
    wire [3:0] valid;
    sample_tick_gen #(.DIVISOR(SAMPLE_DIV)) u_tick (
        .clk_audio_ref(clk_audio_ref),.rst_n(rst_n),.sample_tick(sample_tick));
    generate if(CONTROL_ENABLE!=0)begin : controls
        timbre_blend_smoother u_timbre (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_ce(sample_tick),
            .timbre_select(timbre_select),.blend(timbre_blend),.busy(bright_busy));
    end else begin : fixed_timbre
        assign timbre_blend=0;assign bright_busy=0;
    end endgenerate
    generate if(CONTROL_ENABLE!=0 && ROCK_ENABLE!=0)begin : rock_control
        timbre_blend_smoother u_rock(
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_ce(sample_tick),
            .timbre_select(rock_select),.blend(rock_blend),.busy(rock_busy));
    end else begin : fixed_rock
        assign rock_blend=0;assign rock_busy=0;
    end endgenerate
    always @(posedge clk_audio_ref) begin
        if(!rst_n) begin pending_on<=0; pending_off<=0; end
        else if(sample_tick) begin pending_on<=0; pending_off<=0; end
        else begin pending_on<=pending_on|note_on; pending_off<=pending_off|note_off; end
    end
    genvar g;
    generate for(g=0;g<4;g=g+1) begin : voice
        legacy_piano_voice_core #(.HAMMER_ENABLE(HAMMER_ENABLE),.MODES(MODES),.CONTROL_ENABLE(CONTROL_ENABLE),.ROCK_ENABLE(ROCK_ENABLE)) u_voice (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_ce(sample_tick),
            .note_on(pending_on[g]|note_on[g]),.note_off(pending_off[g]|note_off[g]),
            .velocity_level(velocity_level[g*2+:2]),.phase_inc(phase_inc[g*32+:32]),
            .timbre_blend(timbre_blend),.rock_blend(rock_blend),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),
            .sample_valid(valid[g]),.pcm_out(voice_pcm[g*24+:24]),
            .active(voice_active[g]),.busy(),.deadline_miss(deadline_miss[g]),
            .profile(voice_profile[g*2+:2]));
    end endgenerate
    assign sample_valid=valid[0];
endmodule
