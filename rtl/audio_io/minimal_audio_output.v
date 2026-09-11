`include "../config/guitar_config.vh"

module minimal_audio_output #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV
) (
    input  wire                         clk_audio_ref,
    input  wire                         rst_n,
    input  wire                         note_on,
    input  wire                         note_off,
    input  wire [`PHASE_ACC_BITS-1:0]   phase_inc,

    output wire                         sample_tick,
    output wire                         voice_active,
    output wire                         pcm16_valid,

    output wire                         dac_bclk,
    output wire                         dac_lrck,
    output wire                         dac_din
);

    wire signed [`INTERNAL_PCM_BITS-1:0] voice_pcm;
    wire voice_pcm_valid;

    wire signed [15:0] pcm16_sample;

    voice_audio_core #(
        .SAMPLE_DIV(SAMPLE_DIV)
    ) u_voice_audio_core (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (voice_pcm_valid),
        .pcm_out      (voice_pcm),
        .env_level    (),
        .active       (voice_active)
    );

    pcm24_to_16 u_pcm24_to_16 (
        .clk         (clk_audio_ref),
        .rst_n       (rst_n),
        .pcm_valid   (voice_pcm_valid),
        .pcm_in      (voice_pcm),
        .sample_valid(pcm16_valid),
        .sample_out  (pcm16_sample)
    );

    pt8211_tx u_pt8211_tx (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .sample_valid (pcm16_valid),
        .sample_left  (pcm16_sample),
        .sample_right (pcm16_sample),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

endmodule