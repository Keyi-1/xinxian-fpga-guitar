`include "../config/guitar_config.vh"

// Audio integration top. The physical matrix and pluck interfaces remain
// separate from their future board-specific ADC and I/O glue.
module guitar_audio_top #(
    parameter integer MATRIX_CLK_DIV         = 50000,
    parameter integer MATRIX_SETTLE_CYCLES   = 1,
    parameter integer MATRIX_DEBOUNCE_FRAMES = `DEBOUNCE_SCANS,
    parameter integer SAMPLE_DIV             = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV         = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES           = `SLIDE_SAMPLES,
    parameter integer ADC_SPI_CLK_DIV         = `ADC_SPI_CLK_DIV,
    parameter integer ADC_DEAD_SAMPLES        = `RETRIGGER_DEAD_SAMPLES,
    parameter integer USE_HARMONIC            = 0
) (
    input  wire        sys_clk_50m,
    input  wire        audio_clk_12m288,
    input  wire        rst_n,
    input  wire [7:0]  fret_col_in_n,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,
    input  wire        timbre_select,
    input  wire        chorus_enable,
    input  wire        sustain_reverb_enable,

    output wire [3:0]  fret_row_oe,
    output wire [3:0]  fret_row_drive_n,
    output wire         dac_bclk,
    output wire         dac_lrck,
    output wire         dac_din,

    output wire [31:0] stable_fret_mask,
    output wire [15:0] stable_fret_id,
    output wire [3:0]  audio_voice_active,
    output wire [7:0]  velocity_level,
    output wire [47:0] raw_adc,
    output wire [47:0] peak_adc,
    output wire [31:0] event_timestamp,
    output wire        final_pcm_valid,
    output wire signed [23:0] final_pcm
);

    wire        stable_valid_sys;
    wire        stable_valid_audio;
    wire [15:0] stable_fret_id_audio;
    wire [3:0]  pluck_valid_sys;
    wire [3:0]  pluck_valid_audio;
    wire [7:0]  velocity_level_audio;
    wire        sys_rst_n;
    wire        audio_rst_n;

    reset_sync u_sys_reset_sync (
        .clk(sys_clk_50m), .arst_n(rst_n), .srst_n(sys_rst_n)
    );

    reset_sync u_audio_reset_sync (
        .clk(audio_clk_12m288), .arst_n(rst_n), .srst_n(audio_rst_n)
    );

    matrix_scanner #(
        .CLK_DIV        (MATRIX_CLK_DIV),
        .SETTLE_CYCLES  (MATRIX_SETTLE_CYCLES),
        .DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES)
    ) u_matrix_scanner (
        .clk             (sys_clk_50m),
        .rst_n           (sys_rst_n),
        .col_in_n        (fret_col_in_n),
        .row_oe          (fret_row_oe),
        .row_drive_n     (fret_row_drive_n),
        .frame_valid     (),
        .fret_mask       (),
        .fret_id         (),
        .stable_valid    (stable_valid_sys),
        .stable_fret_mask(stable_fret_mask),
        .stable_fret_id  (stable_fret_id)
    );

    stable_fret_cdc u_stable_fret_cdc (
        .src_clk    (sys_clk_50m),
        .src_rst_n  (sys_rst_n),
        .src_valid  (stable_valid_sys),
        .src_fret_id(stable_fret_id),
        .dst_clk    (audio_clk_12m288),
        .dst_rst_n  (audio_rst_n),
        .dst_valid  (stable_valid_audio),
        .dst_fret_id(stable_fret_id_audio)
    );

    mcp3208_pluck_frontend #(
        .SPI_CLK_DIV (ADC_SPI_CLK_DIV),
        .DEAD_SAMPLES(ADC_DEAD_SAMPLES)
    ) u_mcp3208_pluck_frontend (
        .clk            (sys_clk_50m),
        .rst_n          (sys_rst_n),
        .adc_cs_n       (adc_cs_n),
        .adc_sclk       (adc_sclk),
        .adc_mosi       (adc_mosi),
        .adc_miso       (adc_miso),
        .pluck_valid    (pluck_valid_sys),
        .velocity_level (velocity_level),
        .raw_adc        (raw_adc),
        .peak_adc       (peak_adc),
        .event_timestamp(event_timestamp)
    );

    pluck_event_cdc u_pluck_event_cdc (
        .src_clk  (sys_clk_50m),
        .src_rst_n(sys_rst_n),
        .src_event(pluck_valid_sys),
        .src_velocity_level(velocity_level),
        .dst_clk  (audio_clk_12m288),
        .dst_rst_n(audio_rst_n),
        .dst_event(pluck_valid_audio),
        .dst_velocity_level(velocity_level_audio)
    );

    generate
        if (USE_HARMONIC == 0) begin : u_sine_audio_path
            four_string_audio_chain #(
                .SAMPLE_DIV(SAMPLE_DIV), .REF_DIV(PT8211_REF_DIV),
                .SLIDE_SAMPLES(SLIDE_SAMPLES)
            ) u_four_string_audio_chain (
                .clk_audio_ref(audio_clk_12m288), .rst_n(audio_rst_n),
                .stable_valid(stable_valid_audio), .stable_fret_id(stable_fret_id_audio),
                .pluck_valid(pluck_valid_audio), .velocity_level(velocity_level_audio),
                .note_on(), .note_off(), .slide_valid(), .control_voice_active(),
                .current_fret_id(), .target_phase_inc(), .phase_inc(), .slide_busy(),
                .sample_tick(), .pcm_mix_valid(final_pcm_valid),
                .pcm_mix(final_pcm),
                .audio_voice_active(audio_voice_active), .voice_pcm(),
                .pcm16_valid(), .pcm16_out(), .dac_bclk(dac_bclk),
                .dac_lrck(dac_lrck), .dac_din(dac_din)
            );
        end
        else begin : u_harmonic_audio_path
            four_string_harmonic_audio_chain #(
                .SAMPLE_DIV(SAMPLE_DIV), .REF_DIV(PT8211_REF_DIV),
                .SLIDE_SAMPLES(SLIDE_SAMPLES)
            ) u_four_string_harmonic_audio_chain (
                .clk_audio_ref(audio_clk_12m288), .rst_n(audio_rst_n),
                .stable_valid(stable_valid_audio), .stable_fret_id(stable_fret_id_audio),
                .pluck_valid(pluck_valid_audio), .velocity_level(velocity_level_audio),
                .timbre_select(timbre_select),
                .chorus_enable(chorus_enable),
                .sustain_reverb_enable(sustain_reverb_enable),
                .note_on(), .note_off(), .slide_valid(), .control_voice_active(),
                .current_fret_id(), .target_phase_inc(), .phase_inc(), .slide_busy(),
                .sample_tick(), .pcm_mix_valid(final_pcm_valid),
                .pcm_mix(final_pcm),
                .audio_voice_active(audio_voice_active), .voice_pcm(),
                .timbre_blend(), .timbre_busy(),
                .chorus_blend(), .chorus_busy(),
                .reverb_blend(), .reverb_busy(),
                .pcm16_valid(), .pcm16_out(), .dac_bclk(dac_bclk),
                .dac_lrck(dac_lrck), .dac_din(dac_din)
            );
        end
    endgenerate

endmodule
