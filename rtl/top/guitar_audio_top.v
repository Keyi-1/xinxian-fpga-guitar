`include "../config/guitar_config.vh"

// Shared audio integration: synchronized matrix inputs and board-verified ADC
// detection feed sample-aligned string control in one audio-clock domain.
module guitar_audio_top #(
    parameter integer MATRIX_CLK_DIV         = `MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES   = `MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES = `DEBOUNCE_SCANS,
    parameter integer SAMPLE_DIV             = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV         = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES           = `SLIDE_SAMPLES,
    parameter integer ADC_SPI_CLK_DIV         = `ADC_SPI_CLK_DIV,
    parameter integer ADC_DEAD_SAMPLES        = `RETRIGGER_DEAD_SAMPLES,
    parameter integer ADC_SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE,
    parameter integer USE_HARMONIC            = 0,
    parameter integer ANTI_BEAT_ENABLE = `BOARD_ANTI_BEAT_ENABLE,
    parameter integer ANTI_BEAT_GAP_HZ = 80,
    parameter [8:0] ANTI_BEAT_PAIR_GAIN_Q8 = 9'd128,
    parameter integer PLUCK_ATTACK_SAMPLES = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES = 9600,
    parameter integer PLUCK_FAST_SHIFT = 13,
    parameter integer PLUCK_SLOW_SHIFT = 16,
    parameter integer PLUCK_RELEASE_SHIFT = 10,
    parameter integer PLUCK_IDLE_LEVEL = 64
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
    output wire [3:0]  pluck_events,
    output wire        final_pcm_valid,
    output wire signed [23:0] final_pcm
);

    wire audio_rst_n;
    reset_sync u_audio_reset_sync (
        .clk(audio_clk_12m288), .arst_n(rst_n), .srst_n(audio_rst_n)
    );
    reg [7:0] col_meta_n, col_sync_n;
    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin col_meta_n <= 8'hff; col_sync_n <= 8'hff; end
        else begin col_meta_n <= fret_col_in_n; col_sync_n <= col_meta_n; end
    end
    wire stable_valid_audio;
    wire [3:0] pluck_valid_audio;
    assign pluck_events = pluck_valid_audio;
    matrix_scanner #(
        .CLK_DIV(MATRIX_CLK_DIV), .SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES)
    ) u_matrix_scanner (
        .clk(audio_clk_12m288), .rst_n(audio_rst_n), .col_in_n(col_sync_n),
        .row_oe(fret_row_oe), .row_drive_n(fret_row_drive_n),
        .frame_valid(), .fret_mask(), .fret_id(), .stable_valid(stable_valid_audio),
        .stable_fret_mask(stable_fret_mask), .stable_fret_id(stable_fret_id)
    );
    mcp3208_pluck_frontend #(
        .SPI_CLK_DIV(ADC_SPI_CLK_DIV), .DEAD_SAMPLES(ADC_DEAD_SAMPLES),
        .SETTLE_SAMPLES(ADC_SETTLE_SAMPLES),
        .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE)
    ) u_mcp3208_pluck_frontend (
        .clk(audio_clk_12m288), .rst_n(audio_rst_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .pluck_valid(pluck_valid_audio), .velocity_level(velocity_level),
        .raw_adc(raw_adc), .peak_adc(peak_adc), .event_timestamp(event_timestamp)
    );
    four_string_board_audio_chain #(
        .SAMPLE_DIV(SAMPLE_DIV), .REF_DIV(PT8211_REF_DIV),
        .SLIDE_SAMPLES(SLIDE_SAMPLES), .USE_HARMONIC(USE_HARMONIC),
        .ANTI_BEAT_ENABLE(ANTI_BEAT_ENABLE), .ANTI_BEAT_GAP_HZ(ANTI_BEAT_GAP_HZ),
        .ANTI_BEAT_PAIR_GAIN_Q8(ANTI_BEAT_PAIR_GAIN_Q8),
        .PLUCK_ATTACK_SAMPLES(PLUCK_ATTACK_SAMPLES),
        .PLUCK_FAST_DECAY_SAMPLES(PLUCK_FAST_DECAY_SAMPLES),
        .PLUCK_FAST_SHIFT(PLUCK_FAST_SHIFT), .PLUCK_SLOW_SHIFT(PLUCK_SLOW_SHIFT),
        .PLUCK_RELEASE_SHIFT(PLUCK_RELEASE_SHIFT), .PLUCK_IDLE_LEVEL(PLUCK_IDLE_LEVEL)
    ) u_board_audio_chain (
        .clk_audio_ref(audio_clk_12m288), .rst_n(audio_rst_n),
        .stable_valid(stable_valid_audio), .stable_fret_id(stable_fret_id),
        .pluck_valid(pluck_valid_audio), .velocity_level(velocity_level),
        .timbre_select(timbre_select), .chorus_enable(chorus_enable),
        .sustain_reverb_enable(sustain_reverb_enable),
        .sample_tick(), .pcm_mix_valid(final_pcm_valid), .pcm_mix(final_pcm),
        .voice_active(audio_voice_active), .voice_pcm(),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din)
    );
endmodule
