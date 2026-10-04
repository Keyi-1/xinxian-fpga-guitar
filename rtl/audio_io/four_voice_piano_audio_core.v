`include "../config/guitar_config.vh"
module four_voice_piano_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer HAMMER_ENABLE = 1
) (
    input wire clk_audio_ref, rst_n,
    input wire [3:0] note_on, note_off,
    input wire [7:0] velocity_level,
    input wire [127:0] phase_inc,
    output wire sample_tick, sample_valid,
    output wire [3:0] voice_active,
    output wire [95:0] voice_pcm,
    output wire [7:0] voice_profile,
    output wire [3:0] deadline_miss
);
    reg [3:0] pending_on, pending_off;
    wire [3:0] valid;
    sample_tick_gen #(.DIVISOR(SAMPLE_DIV)) u_tick (
        .clk_audio_ref(clk_audio_ref),.rst_n(rst_n),.sample_tick(sample_tick));
    always @(posedge clk_audio_ref) begin
        if(!rst_n) begin pending_on<=0; pending_off<=0; end
        else if(sample_tick) begin pending_on<=0; pending_off<=0; end
        else begin pending_on<=pending_on|note_on; pending_off<=pending_off|note_off; end
    end
    genvar g;
    generate for(g=0;g<4;g=g+1) begin : voice
        piano_voice_core #(.HAMMER_ENABLE(HAMMER_ENABLE)) u_voice (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_ce(sample_tick),
            .note_on(pending_on[g]|note_on[g]),.note_off(pending_off[g]|note_off[g]),
            .velocity_level(velocity_level[g*2+:2]),.phase_inc(phase_inc[g*32+:32]),
            .sample_valid(valid[g]),.pcm_out(voice_pcm[g*24+:24]),
            .active(voice_active[g]),.busy(),.deadline_miss(deadline_miss[g]),
            .profile(voice_profile[g*2+:2]));
    end endgenerate
    assign sample_valid=valid[0];
endmodule
