`include "../config/guitar_config.vh"

// Optional harmonic counterpart of four_voice_audio_output. The existing
// sine-only output module remains the default production path.
module four_voice_harmonic_audio_output #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer REF_DIV    = `PT8211_REF_DIV,
    parameter integer HARMONICS  = `HARMONICS_MAX
) (
    input  wire          clk_audio_ref,
    input  wire          rst_n,
    input  wire [3:0]    note_on,
    input  wire [3:0]    note_off,
    input  wire [7:0]    velocity_level,
    input  wire [127:0]  phase_inc,
    input  wire          timbre_select,
    input  wire          chorus_enable,
    input  wire          sustain_reverb_enable,

    output wire          sample_tick,
    output wire          pcm_mix_valid,
    output wire signed [23:0] pcm_mix,
    output wire [3:0]    voice_active,
    output wire signed [95:0] voice_pcm,
    output wire [3:0]    voice_busy,
    output wire [3:0]    deadline_miss,
    output wire [8:0]    timbre_blend,
    output wire          timbre_busy,
    output wire [8:0]    chorus_blend,
    output wire          chorus_busy,
    output wire [8:0]    reverb_blend,
    output wire          reverb_busy,
    output wire          pcm16_valid,
    output wire signed [15:0] pcm16_out,
    output wire          dac_bclk,
    output wire          dac_lrck,
    output wire          dac_din
);

    wire                 pcm_mix_raw_valid;
    wire signed [23:0]   pcm_mix_raw;
    wire                 pcm_clip_valid;
    wire signed [23:0]   pcm_clip;
    wire                 pcm_chorus_valid;
    wire signed [23:0]   pcm_chorus;
    reg [1:0]            rock_drive_level;

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(SAMPLE_DIV),
        .HARMONICS (HARMONICS)
    ) u_four_voice_harmonic_audio_core (
        .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
        .note_on(note_on), .note_off(note_off),
        .velocity_level(velocity_level), .phase_inc(phase_inc),
        .timbre_select(timbre_select),
        .sustain_enable(sustain_reverb_enable),
        .sample_tick(sample_tick), .sample_valid(pcm_mix_raw_valid),
        .pcm_mix(pcm_mix_raw), .voice_active(voice_active),
        .voice_pcm(voice_pcm), .voice_busy(voice_busy),
        .deadline_miss(deadline_miss), .timbre_blend(timbre_blend),
        .timbre_busy(timbre_busy)
    );

    always @* begin
        rock_drive_level = 2'd0;
        if (voice_active[0])
            rock_drive_level = velocity_level[1:0];
        if (voice_active[1] &&
            (velocity_level[3:2] > rock_drive_level))
            rock_drive_level = velocity_level[3:2];
        if (voice_active[2] &&
            (velocity_level[5:4] > rock_drive_level))
            rock_drive_level = velocity_level[5:4];
        if (voice_active[3] &&
            (velocity_level[7:6] > rock_drive_level))
            rock_drive_level = velocity_level[7:6];
    end

    pcm24_rock_soft_clip u_pcm24_rock_soft_clip (
        .clk            (clk_audio_ref),
        .rst_n          (rst_n),
        .sample_valid_in(pcm_mix_raw_valid),
        .pcm_in         (pcm_mix_raw),
        .drive_level    (rock_drive_level),
        .timbre_blend   (timbre_blend),
        .sample_valid   (pcm_clip_valid),
        .pcm_out        (pcm_clip)
    );

    pcm24_chorus u_pcm24_chorus (
        .clk            (clk_audio_ref),
        .rst_n          (rst_n),
        .sample_valid_in(pcm_clip_valid),
        .pcm_in         (pcm_clip),
        .chorus_enable  (chorus_enable),
        .sample_valid   (pcm_chorus_valid),
        .pcm_out        (pcm_chorus),
        .effect_blend   (chorus_blend),
        .effect_busy    (chorus_busy),
        .lfo_position   ()
    );

    pcm24_reverb u_pcm24_reverb (
        .clk            (clk_audio_ref),
        .rst_n          (rst_n),
        .sample_valid_in(pcm_chorus_valid),
        .pcm_in         (pcm_chorus),
        .reverb_enable  (sustain_reverb_enable),
        .sample_valid   (pcm_mix_valid),
        .pcm_out        (pcm_mix),
        .effect_blend   (reverb_blend),
        .effect_busy    (reverb_busy)
    );

    pcm24_to_16 u_pcm24_to_16 (
        .clk(clk_audio_ref), .rst_n(rst_n),
        .pcm_valid(pcm_mix_valid), .pcm_in(pcm_mix),
        .sample_valid(pcm16_valid), .sample_out(pcm16_out)
    );

    pt8211_tx #(.REF_DIV(REF_DIV)) u_pt8211_tx (
        .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
        .sample_valid(pcm16_valid), .sample_left(pcm16_out),
        .sample_right(pcm16_out),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din)
    );

endmodule
