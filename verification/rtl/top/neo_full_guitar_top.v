`include "../config/guitar_config.vh"

// Tang Mega NEO electrical-boundary wrapper for the FULL logical design.
// Panel defaults match the delivered 480x272 screen. An integrated FULL
// build still needs its board clock/pin wrapper; the standalone RGB demo
// provides the measured 8.333 MHz clock and fixed NEO Dock pin locations.
module neo_full_guitar_top #(
    parameter integer MATRIX_CLK_DIV = `MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES = `MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES = `DEBOUNCE_SCANS,
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer ADC_SPI_CLK_DIV = `ADC_SPI_CLK_DIV,
    parameter integer ADC_DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer ADC_SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE,
    parameter integer USE_HARMONIC = 1,
    parameter integer USE_PIANO = 1,
    parameter integer PIANO_MODES = 32,
    parameter integer PIANO_CONTROL_ENABLE = 1,
    parameter integer PIANO_ROCK_ENABLE = 1,
    parameter integer ANTI_BEAT_ENABLE = `BOARD_ANTI_BEAT_ENABLE,
    parameter integer FFT_FRAME_GAP_SAMPLES = 512,
    parameter integer H_ACTIVE = 480,
    parameter integer H_FRONT = 8,
    parameter integer H_SYNC = 4,
    parameter integer H_BACK = 39,
    parameter integer V_ACTIVE = 272,
    parameter integer V_FRONT = 8,
    parameter integer V_SYNC = 4,
    parameter integer V_BACK = 8,
    parameter integer BAR_SLOT = 15,
    parameter integer BAR_WIDTH = 12,
    parameter integer KEY_DEBOUNCE_CYCLES = 245760,
    parameter integer KEY_LONG_PRESS_CYCLES = 12288000,
    parameter integer LCD_PCLK_INVERT = 1,
    parameter integer LCD_BL_ACTIVE_HIGH = 1
) (
    input  wire        sys_clk_50m,
    input  wire        audio_clk_12m288,
    input  wire        pixel_clk,
    input  wire        rst_n,

    inout  wire [3:0]  fret_row_n,
    input  wire [7:0]  fret_col_in_n,

    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,

    input  wire        key_timbre_n,
    input  wire        key_chorus_n,
    input  wire        key_sustain_n,

    output wire        dac_bclk,
    output wire        dac_lrck,
    output wire        dac_din,
    output wire        pa_en_n,

    output wire        lcd_pclk,
    output wire        lcd_backlight,
    output wire        lcd_hsync,
    output wire        lcd_vsync,
    output wire        lcd_de,
    output wire [7:0]  lcd_r,
    output wire [7:0]  lcd_g,
    output wire [7:0]  lcd_b
);

    wire [3:0] fret_row_oe_internal;
    wire [3:0] fret_row_drive_n_internal;
    wire [3:0] audio_voice_active_internal;
    wire       core_pa_enable;
    wire       spectrum_frame_update_internal;
    wire       display_frame_update_internal;
    wire       display_cdc_overrun_internal;

    wire timbre_select_audio,chorus_enable_audio,sustain_enable_audio;
    wire rock_select_audio;
    wire reverb_enable_audio,harmony_enable_audio;
    wire [1:0] space_mode_audio;
    wire audio_control_rst_n;
    reset_sync u_audio_control_reset_sync (
        .clk(audio_clk_12m288),.arst_n(rst_n),.srst_n(audio_control_rst_n));
    // Condition the asynchronous physical keys directly in the audio domain;
    // the multi-state space selector therefore needs no multi-bit CDC.
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES),
        .LONG_PRESS_CYCLES(KEY_LONG_PRESS_CYCLES)) u_buttons (
        .clk(audio_clk_12m288),.rst_n(audio_control_rst_n),
        .key_timbre_n(key_timbre_n),.key_chorus_n(key_chorus_n),.key_space_n(key_sustain_n),
        .timbre_select(timbre_select_audio),.rock_select(rock_select_audio),.timbre_mode(),.chorus_enable(chorus_enable_audio),
        .sustain_enable(sustain_enable_audio),.reverb_enable(reverb_enable_audio),
        .space_mode(space_mode_audio),.harmony_enable(harmony_enable_audio));

    genvar row_index;
    generate
        for (row_index = 0; row_index < 4; row_index = row_index + 1) begin : g_fret_row_tristate
            assign fret_row_n[row_index] = fret_row_oe_internal[row_index]
                                          ? fret_row_drive_n_internal[row_index]
                                          : 1'bz;
        end
    endgenerate

    full_guitar_top #(
        .MATRIX_CLK_DIV(MATRIX_CLK_DIV),
        .MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),
        .SAMPLE_DIV(SAMPLE_DIV), .PT8211_REF_DIV(PT8211_REF_DIV),
        .SLIDE_SAMPLES(SLIDE_SAMPLES),
        .ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),
        .ADC_DEAD_SAMPLES(ADC_DEAD_SAMPLES),
        .ADC_SETTLE_SAMPLES(ADC_SETTLE_SAMPLES),
        .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE), .USE_HARMONIC(USE_HARMONIC),
        .USE_PIANO(USE_PIANO),.PIANO_MODES(PIANO_MODES),.PIANO_CONTROL_ENABLE(PIANO_CONTROL_ENABLE),
        .PIANO_ROCK_ENABLE(PIANO_ROCK_ENABLE),
        .ANTI_BEAT_ENABLE(ANTI_BEAT_ENABLE),
        .FFT_FRAME_GAP_SAMPLES(FFT_FRAME_GAP_SAMPLES),
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC),
        .H_BACK(H_BACK), .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC), .V_BACK(V_BACK), .BAR_SLOT(BAR_SLOT),
        .BAR_WIDTH(BAR_WIDTH)
    ) u_full_guitar_top (
        .sys_clk_50m(sys_clk_50m),
        .audio_clk_12m288(audio_clk_12m288),
        .pixel_clk(pixel_clk), .rst_n(rst_n),
        .fret_col_in_n(fret_col_in_n), .adc_miso(adc_miso),
        .timbre_select(timbre_select_audio),
        .rock_select(rock_select_audio),
        .chorus_enable(chorus_enable_audio),
        .sustain_enable(sustain_enable_audio),.reverb_enable(reverb_enable_audio),
        .harmony_enable(harmony_enable_audio),
        .fret_row_oe(fret_row_oe_internal),
        .fret_row_drive_n(fret_row_drive_n_internal),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi), .dac_bclk(dac_bclk),
        .dac_lrck(dac_lrck), .dac_din(dac_din),
        .pa_en(core_pa_enable), .lcd_hsync(lcd_hsync),
        .lcd_vsync(lcd_vsync), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .audio_voice_active(audio_voice_active_internal),
        .spectrum_frame_update(spectrum_frame_update_internal),
        .display_frame_update(display_frame_update_internal),
        .display_cdc_overrun(display_cdc_overrun_internal)
    );

    // NEO amplifier mute is high; the core stays enabled after audio reset.
    assign pa_en_n = rst_n ? ~core_pa_enable : 1'b1;

    // Keep pixel-clock polarity and backlight polarity explicit until the
    // exact LCD panel is frozen. Defaults match the reviewed NEO boundary.
    assign lcd_pclk = LCD_PCLK_INVERT ? ~pixel_clk : pixel_clk;
    assign lcd_backlight = rst_n
                           ? (LCD_BL_ACTIVE_HIGH ? 1'b1 : 1'b0)
                           : (LCD_BL_ACTIVE_HIGH ? 1'b0 : 1'b1);

endmodule
