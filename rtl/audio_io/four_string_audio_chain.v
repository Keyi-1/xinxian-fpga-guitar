`include "../config/guitar_config.vh"

// Complete four-string path from stable fret and pluck events to PT8211.
module four_string_audio_chain #(
    parameter integer SAMPLE_DIV    = `AUDIO_SAMPLE_DIV,
    parameter integer REF_DIV       = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES
) (
    input  wire         clk_audio_ref,
    input  wire         rst_n,
    input  wire         stable_valid,
    input  wire [15:0]  stable_fret_id,
    input  wire [3:0]   pluck_valid,
    input  wire [7:0]   velocity_level,

    output wire [3:0]   note_on,
    output wire [3:0]   note_off,
    output wire [3:0]   slide_valid,
    output wire [3:0]   control_voice_active,
    output wire [15:0]  current_fret_id,
    output wire [127:0] target_phase_inc,
    output wire [127:0] phase_inc,
    output wire [3:0]   slide_busy,

    output wire         sample_tick,
    output wire         pcm_mix_valid,
    output wire signed [23:0] pcm_mix,
    output wire [3:0]   audio_voice_active,
    output wire signed [95:0] voice_pcm,
    output wire         pcm16_valid,
    output wire signed [15:0] pcm16_out,

    output wire         dac_bclk,
    output wire         dac_lrck,
    output wire         dac_din
);

    four_string_voice_control #(
        .SLIDE_SAMPLES(SLIDE_SAMPLES)
    ) u_four_string_voice_control (
        .clk             (clk_audio_ref),
        .rst_n           (rst_n),
        .stable_valid    (stable_valid),
        .stable_fret_id  (stable_fret_id),
        .pluck_valid     (pluck_valid),
        .sample_ce       (sample_tick),
        .note_on         (note_on),
        .note_off        (note_off),
        .slide_valid     (slide_valid),
        .voice_active    (control_voice_active),
        .current_fret_id (current_fret_id),
        .target_phase_inc(target_phase_inc),
        .phase_inc       (phase_inc),
        .slide_busy      (slide_busy)
    );

    four_voice_audio_output #(
        .SAMPLE_DIV(SAMPLE_DIV),
        .REF_DIV   (REF_DIV)
    ) u_four_voice_audio_output (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .velocity_level(velocity_level),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .pcm_mix_valid(pcm_mix_valid),
        .pcm_mix      (pcm_mix),
        .voice_active (audio_voice_active),
        .voice_pcm    (voice_pcm),
        .pcm16_valid  (pcm16_valid),
        .pcm16_out    (pcm16_out),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

endmodule
