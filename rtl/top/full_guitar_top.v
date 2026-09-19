`include "../config/guitar_config.vh"

// FULL logical product top.  All performance-path behavior is RTL; pixel_clk
// is supplied by the board clock/PLL wrapper so this module remains portable.
module full_guitar_top #(
    parameter integer MATRIX_CLK_DIV = 50000,
    parameter integer MATRIX_SETTLE_CYCLES = 1,
    parameter integer MATRIX_DEBOUNCE_FRAMES = `DEBOUNCE_SCANS,
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer ADC_SPI_CLK_DIV = `ADC_SPI_CLK_DIV,
    parameter integer ADC_DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer FFT_FRAME_GAP_SAMPLES = 512,
    parameter integer H_ACTIVE = 800,
    parameter integer H_FRONT = 40,
    parameter integer H_SYNC = 128,
    parameter integer H_BACK = 88,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT = 13,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 31,
    parameter integer BAR_SLOT = 25,
    parameter integer BAR_WIDTH = 21
) (
    input  wire        sys_clk_50m,
    input  wire        audio_clk_12m288,
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire [7:0]  fret_col_in_n,
    input  wire        adc_miso,
    input  wire        timbre_select,
    input  wire        chorus_enable,
    input  wire        sustain_reverb_enable,

    output wire [3:0]  fret_row_oe,
    output wire [3:0]  fret_row_drive_n,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    output wire        dac_bclk,
    output wire        dac_lrck,
    output wire        dac_din,
    output wire        pa_en,
    output wire        lcd_hsync,
    output wire        lcd_vsync,
    output wire        lcd_de,
    output wire [7:0]  lcd_r,
    output wire [7:0]  lcd_g,
    output wire [7:0]  lcd_b,
    output wire [3:0]  audio_voice_active,
    output wire        spectrum_frame_update,
    output wire        display_frame_update,
    output wire        display_cdc_overrun
);

    wire final_pcm_valid;
    wire signed [23:0] final_pcm;

    guitar_audio_top #(
        .MATRIX_CLK_DIV(MATRIX_CLK_DIV),
        .MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),
        .SAMPLE_DIV(SAMPLE_DIV), .PT8211_REF_DIV(PT8211_REF_DIV),
        .SLIDE_SAMPLES(SLIDE_SAMPLES), .ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),
        .ADC_DEAD_SAMPLES(ADC_DEAD_SAMPLES), .USE_HARMONIC(1)
    ) u_guitar_audio_top (
        .sys_clk_50m(sys_clk_50m), .audio_clk_12m288(audio_clk_12m288),
        .rst_n(rst_n), .fret_col_in_n(fret_col_in_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .timbre_select(timbre_select),
        .chorus_enable(chorus_enable),
        .sustain_reverb_enable(sustain_reverb_enable),
        .fret_row_oe(fret_row_oe), .fret_row_drive_n(fret_row_drive_n),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din),
        .stable_fret_mask(), .stable_fret_id(),
        .audio_voice_active(audio_voice_active), .velocity_level(),
        .raw_adc(), .peak_adc(), .event_timestamp(),
        .final_pcm_valid(final_pcm_valid), .final_pcm(final_pcm)
    );

    spectrum_display_top #(
        .FFT_FRAME_GAP_SAMPLES(FFT_FRAME_GAP_SAMPLES),
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC),
        .H_BACK(H_BACK), .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC), .V_BACK(V_BACK), .BAR_SLOT(BAR_SLOT),
        .BAR_WIDTH(BAR_WIDTH)
    ) u_spectrum_display_top (
        .audio_clk(audio_clk_12m288), .pixel_clk(pixel_clk), .rst_n(rst_n),
        .pcm_valid(final_pcm_valid), .pcm_in(final_pcm),
        .lcd_hsync(lcd_hsync), .lcd_vsync(lcd_vsync), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .spectrum_frame_update(spectrum_frame_update),
        .display_frame_update(display_frame_update),
        .cdc_overrun(display_cdc_overrun)
    );

    assign pa_en = |audio_voice_active;

endmodule
