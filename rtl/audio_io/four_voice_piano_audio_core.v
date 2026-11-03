`include "../config/guitar_config.vh"
module four_voice_piano_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer HAMMER_ENABLE = 1,
    parameter integer KS_TDM_ENABLE = 0,
    parameter integer MODES = 8,
    parameter integer CONTROL_ENABLE = 0,
    parameter integer ROCK_ENABLE = 0,
    parameter integer FORCE_RELEASE_ENABLE = 0
) (
    input wire clk_audio_ref, rst_n,clk_synth_ref,
    input wire [3:0] note_on, note_off,
    input wire [7:0] velocity_level,
    input wire [127:0] phase_inc,
    input wire timbre_select, rock_select, sustain_enable, harmony_enable,
    input wire [3:0] force_release,
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
    wire [3:0] valid,modal_deadline,ks_request,ks_strike,ks_enabled,ks_harmony;
    wire [127:0] ks_increment,ks_harmony_increment;
    wire [111:0] ks_value;
    wire ks_busy,ks_overrun;
    assign deadline_miss=modal_deadline | {4{ks_overrun}};
    generate if(KS_TDM_ENABLE!=0)begin:tdm_compute
        wire compute_clk,locked,compute_rst_n;
        ks_compute_pll pll(.clkin(clk_synth_ref),.clkout0(compute_clk),.lock(locked));
        reset_sync reset(.clk(compute_clk),.arst_n(rst_n && locked),.srst_n(compute_rst_n));
        ks_tdm_bank bank(.audio_clk(clk_audio_ref),.audio_rst_n(rst_n),
            .compute_clk(compute_clk),.compute_rst_n(compute_rst_n),.start(ks_request[0]),
            .strike(ks_strike),.enabled(ks_enabled),.harmony(ks_harmony),.sustain(sustain_enable),
            .increment(ks_increment),.harmony_increment(ks_harmony_increment),
            .value(ks_value),.busy(ks_busy),.overrun(ks_overrun));
    end else begin:local_compute
        assign ks_value=0;assign ks_busy=0;assign ks_overrun=0;
    end endgenerate
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
        piano_voice_core #(.HAMMER_ENABLE(HAMMER_ENABLE),
            .KS_EXTERNAL_ENABLE(KS_TDM_ENABLE),.HAMMER_SEED(32'h6d2b79f5 ^ (32'h9e3779b9*g)),
            .MODES(MODES),.CONTROL_ENABLE(CONTROL_ENABLE),.ROCK_ENABLE(ROCK_ENABLE),
            .FORCE_RELEASE_ENABLE(FORCE_RELEASE_ENABLE)) u_voice (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_ce(sample_tick),
            .ks_external_value(ks_value[g*28+:28]),.ks_external_busy(ks_busy),
            .ks_request(ks_request[g]),.ks_strike(ks_strike[g]),.ks_enabled(ks_enabled[g]),
            .ks_harmony_enable(ks_harmony[g]),.ks_increment(ks_increment[g*32+:32]),
            .ks_harmony_increment(ks_harmony_increment[g*32+:32]),.note_on(pending_on[g]|note_on[g]),.note_off(pending_off[g]|note_off[g]),
            .velocity_level(velocity_level[g*2+:2]),.phase_inc(phase_inc[g*32+:32]),
            .timbre_blend(timbre_blend),.rock_blend(rock_blend),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),
            .force_release(force_release[g]),
            .sample_valid(valid[g]),.pcm_out(voice_pcm[g*24+:24]),
            .active(voice_active[g]),.busy(),.deadline_miss(modal_deadline[g]),
            .profile(voice_profile[g*2+:2]));
    end endgenerate
    assign sample_valid=valid[0];
endmodule
