`include "../config/guitar_config.vh"
// Downloadable FULL audio entry for the existing two PCBs and NEO Dock.
// Adds a passive four-voice visual observer; audio configuration stays identical.
// No external reset pin: startup initializes through a short power-on sequencer.
module neo_guitar_radial_top #(
    parameter integer KEY_DEBOUNCE_CYCLES=245760,
    parameter integer KEY_LONG_PRESS_CYCLES=12288000,
    parameter integer MATRIX_CLK_DIV=`MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES=`MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES=`DEBOUNCE_SCANS,
    parameter integer ADC_SPI_CLK_DIV=`ADC_SPI_CLK_DIV,
    parameter integer PLUCK_DEAD_SAMPLES=`RETRIGGER_DEAD_SAMPLES,
    parameter integer PLUCK_SETTLE_SAMPLES=`PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE=`BOARD_FIXED_VELOCITY_ENABLE
)(
    input wire audio_clk_12m288,
    input wire sys_clk_50m,
    input wire USER_BUTTON1_n,USER_BUTTON2_n,USER_BUTTON3_n,
    inout wire ROW0,ROW1,ROW2,ROW3,
    input wire COL0,COL1,COL2,COL3,COL4,COL5,COL6,COL7,
    output wire adc_cs_n,adc_sclk,adc_mosi,
    input wire adc_miso,
    output wire dac_bclk,dac_lrck,dac_din,pa_en_n,
    output wire [3:0] event_led,
    output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
    output wire [5:0] lcd_r,lcd_g,lcd_b
);
    reg [7:0] startup_count=0;
    always @(posedge audio_clk_12m288)
        if(startup_count!=255)startup_count<=startup_count+1'b1;
    wire startup_done=startup_count==255;
    wire audio_rst_n;
    reset_sync u_startup(.clk(audio_clk_12m288),.arst_n(startup_done),.srst_n(audio_rst_n));
    wire timbre_select,chorus_enable,sustain_enable,reverb_enable,harmony_enable;
    wire rock_select;
    wire [1:0] timbre_mode;
    wire [1:0] space_mode;
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES),
        .LONG_PRESS_CYCLES(KEY_LONG_PRESS_CYCLES)) u_buttons (
        .clk(audio_clk_12m288),.rst_n(audio_rst_n),
        .key_timbre_n(USER_BUTTON1_n),.key_chorus_n(USER_BUTTON2_n),.key_space_n(USER_BUTTON3_n),
        .timbre_select(timbre_select),.rock_select(rock_select),.timbre_mode(timbre_mode),.chorus_enable(chorus_enable),
        .sustain_enable(sustain_enable),.reverb_enable(reverb_enable),
        .space_mode(space_mode),.harmony_enable(harmony_enable));
    wire [3:0] row_oe,row_drive_n;
    wire [127:0] visual_phase_inc;
    wire [3:0] visual_note_on,visual_active;
    wire [15:0] visual_fret;
    wire [95:0] visual_pcm;
    wire visual_tick,visual_pcm_valid;
    wire final_pcm_valid;wire signed [23:0] final_pcm;
    wire [399:0] visual_snapshot;
    wire lcd_rst_n;
    reset_sync u_lcd_reset(.clk(sys_clk_50m),.arst_n(audio_rst_n),.srst_n(lcd_rst_n));
    guitar_audio_top #(
        .MATRIX_CLK_DIV(MATRIX_CLK_DIV),.MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),
        .ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),.ADC_DEAD_SAMPLES(PLUCK_DEAD_SAMPLES),
        .ADC_SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES),.FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE),
        .USE_PIANO(1),.PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)
    ) u_audio (
        .sys_clk_50m(1'b0),.audio_clk_12m288(audio_clk_12m288),.rst_n(startup_done),
        .fret_col_in_n({COL7,COL6,COL5,COL4,COL3,COL2,COL1,COL0}),
        .adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),.adc_mosi(adc_mosi),.adc_miso(adc_miso),
        .timbre_select(timbre_select),.rock_select(rock_select),.chorus_enable(chorus_enable),
        .sustain_enable(sustain_enable),.reverb_enable(reverb_enable),.harmony_enable(harmony_enable),
        .fret_row_oe(row_oe),.fret_row_drive_n(row_drive_n),
        .dac_bclk(dac_bclk),.dac_lrck(dac_lrck),.dac_din(dac_din),
        .stable_fret_mask(),.stable_fret_id(visual_fret),.audio_voice_active(visual_active),.velocity_level(),
        .raw_adc(),.peak_adc(),.event_timestamp(),.pluck_events(),.final_pcm_valid(final_pcm_valid),.final_pcm(final_pcm),
        .display_phase_inc(visual_phase_inc),.display_note_on(visual_note_on),
        .display_sample_tick(visual_tick),.display_voice_sample_valid(visual_pcm_valid),
        .display_voice_pcm(visual_pcm));
    guitar_visual_telemetry #(.HOLD_INACTIVE_PITCH(1)) u_telemetry(.clk(audio_clk_12m288),.rst_n(audio_rst_n),
        .sample_tick(visual_tick),.voice_sample_valid(visual_pcm_valid),.phase_inc(visual_phase_inc),
        .note_on(visual_note_on),.voice_active(visual_active),.fret_id(visual_fret),
        .voice_pcm(visual_pcm),.snapshot(visual_snapshot));
    guitar_radial_display u_display(.audio_clk(audio_clk_12m288),.audio_rst_n(audio_rst_n),
        .clk(sys_clk_50m),.rst_n(lcd_rst_n),.audio_snapshot(visual_snapshot),.audio_pcm_valid(final_pcm_valid),.audio_pcm(final_pcm),
        .lcd_pclk(lcd_pclk),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),.lcd_de(lcd_de),
        .lcd_backlight(lcd_backlight),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    assign ROW0=row_oe[0]?row_drive_n[0]:1'bz;
    assign ROW1=row_oe[1]?row_drive_n[1]:1'bz;
    assign ROW2=row_oe[2]?row_drive_n[2]:1'bz;
    assign ROW3=row_oe[3]?row_drive_n[3]:1'bz;
    assign pa_en_n=~audio_rst_n;
    // LED0: off=piano, steady=bright, 2Hz blink=rock; other LEDs keep effects.
    // Harmony status is indicated by both space LEDs while space mode is dry.
    reg [21:0] rock_led_count;
    reg rock_led_on;
    always @(posedge audio_clk_12m288)begin
        if(!audio_rst_n || !rock_select)begin rock_led_count<=0;rock_led_on<=1;end
        else if(rock_led_count==3071999)begin rock_led_count<=0;rock_led_on<=~rock_led_on;end
        else rock_led_count<=rock_led_count+1'b1;
    end
    assign event_led=~{(reverb_enable||(harmony_enable&&space_mode==0)),
                      (sustain_enable||(harmony_enable&&space_mode==0)),chorus_enable,
                      (timbre_select||(rock_select&&rock_led_on))};
endmodule
