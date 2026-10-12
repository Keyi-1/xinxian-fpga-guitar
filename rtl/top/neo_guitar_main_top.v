`include "../config/guitar_config.vh"
// Physical main entry for the current two-PCB instrument and NEO Dock.
// Only confirmed board interfaces are exposed. The LCD-capable FULL wrapper
// remains available separately, with its pixel clock and panel wiring external.
module neo_guitar_main_top #(
    parameter integer MATRIX_CLK_DIV = `MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES = `MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES = `DEBOUNCE_SCANS,
    parameter integer ADC_SPI_CLK_DIV = `ADC_SPI_CLK_DIV,
    parameter integer PLUCK_DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer PLUCK_SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter integer AUDIO_SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer USE_HARMONIC = `BOARD_USE_HARMONIC,
    parameter integer USE_PIANO = `BOARD_USE_PIANO,
    parameter integer PIANO_HAMMER_ENABLE = `BOARD_PIANO_HAMMER_ENABLE,
    parameter integer PIANO_ROOM_ENABLE = `BOARD_PIANO_ROOM_ENABLE,
    parameter integer ANTI_BEAT_ENABLE = `BOARD_ANTI_BEAT_ENABLE,
    parameter integer ANTI_BEAT_GAP_HZ = 80,
    parameter [8:0] ANTI_BEAT_PAIR_GAIN_Q8 = 9'd128,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE,
    parameter integer LED_HOLD_CYCLES = 1200000,
    parameter integer PLUCK_ATTACK_SAMPLES = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES = 9600,
    parameter integer PLUCK_FAST_SHIFT = 13,
    parameter integer PLUCK_SLOW_SHIFT = 16,
    parameter integer PLUCK_RELEASE_SHIFT = 10,
    parameter integer PLUCK_IDLE_LEVEL = 64
) (
    input wire audio_clk_12m288, rst_n,
    inout wire ROW0, ROW1, ROW2, ROW3,
    input wire COL0, COL1, COL2, COL3, COL4, COL5, COL6, COL7,
    output wire adc_cs_n, adc_sclk, adc_mosi,
    input wire adc_miso,
    output wire dac_bclk, dac_lrck, dac_din, pa_en_n,
    output wire [3:0] event_led
);
    wire [3:0] row_oe, row_drive_n;
    wire [3:0] pluck_events;
    wire audio_rst_n;
    reset_sync u_reset (.clk(audio_clk_12m288), .arst_n(rst_n), .srst_n(audio_rst_n));
    guitar_audio_top #(
        .MATRIX_CLK_DIV(MATRIX_CLK_DIV), .MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),
        .SAMPLE_DIV(AUDIO_SAMPLE_DIV), .PT8211_REF_DIV(PT8211_REF_DIV),
        .SLIDE_SAMPLES(SLIDE_SAMPLES), .ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),
        .ADC_DEAD_SAMPLES(PLUCK_DEAD_SAMPLES), .ADC_SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES),
        .USE_HARMONIC(USE_HARMONIC), .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE),
        .USE_PIANO(USE_PIANO), .PIANO_HAMMER_ENABLE(PIANO_HAMMER_ENABLE),
        .PIANO_ROOM_ENABLE(PIANO_ROOM_ENABLE),
        .ANTI_BEAT_ENABLE(ANTI_BEAT_ENABLE), .ANTI_BEAT_GAP_HZ(ANTI_BEAT_GAP_HZ),
        .ANTI_BEAT_PAIR_GAIN_Q8(ANTI_BEAT_PAIR_GAIN_Q8),
        .PLUCK_ATTACK_SAMPLES(PLUCK_ATTACK_SAMPLES),
        .PLUCK_FAST_DECAY_SAMPLES(PLUCK_FAST_DECAY_SAMPLES),
        .PLUCK_FAST_SHIFT(PLUCK_FAST_SHIFT), .PLUCK_SLOW_SHIFT(PLUCK_SLOW_SHIFT),
        .PLUCK_RELEASE_SHIFT(PLUCK_RELEASE_SHIFT), .PLUCK_IDLE_LEVEL(PLUCK_IDLE_LEVEL)
    ) u_audio (
        .sys_clk_50m(1'b0), .audio_clk_12m288(audio_clk_12m288), .rst_n(rst_n),
        .fret_col_in_n({COL7,COL6,COL5,COL4,COL3,COL2,COL1,COL0}),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .timbre_select(1'b0),.rock_select(1'b0), .chorus_enable(1'b0), .sustain_enable(1'b0),.reverb_enable(1'b0),.harmony_enable(1'b0),
        .fret_row_oe(row_oe), .fret_row_drive_n(row_drive_n),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din),
        .stable_fret_mask(), .stable_fret_id(), .audio_voice_active(),
        .velocity_level(), .raw_adc(), .peak_adc(), .event_timestamp(),
        .pluck_events(pluck_events), .final_pcm_valid(), .final_pcm()
    ,
        .display_phase_inc(),.display_note_on(),.display_sample_tick(),.display_voice_sample_valid(),.display_voice_pcm());
    assign ROW0 = row_oe[0] ? row_drive_n[0] : 1'bz;
    assign ROW1 = row_oe[1] ? row_drive_n[1] : 1'bz;
    assign ROW2 = row_oe[2] ? row_drive_n[2] : 1'bz;
    assign ROW3 = row_oe[3] ? row_drive_n[3] : 1'bz;
    assign pa_en_n = audio_rst_n ? 1'b0 : 1'b1;
    reg [31:0] led_stretch [0:3];
    // Debug LEDs use the frontend events, with no influence on sound.
    integer i;
    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            for (i = 0; i < 4; i = i + 1) led_stretch[i] <= 0;
        end
        else begin
            for (i = 0; i < 4; i = i + 1) begin
                if (pluck_events[i]) led_stretch[i] <= LED_HOLD_CYCLES;
                else if (led_stretch[i] != 0) led_stretch[i] <= led_stretch[i] - 1'b1;
            end
        end
    end
    assign event_led = {led_stretch[3] == 0,led_stretch[2] == 0,
                        led_stretch[1] == 0,led_stretch[0] == 0};
endmodule
