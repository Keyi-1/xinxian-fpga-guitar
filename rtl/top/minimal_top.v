`include "../config/guitar_config.vh"

module minimal_top #(
    parameter integer SAMPLE_DIV      = `AUDIO_SAMPLE_DIV,
    parameter integer LED_HALF_PERIOD = 25000000
) (
    input  wire                       sys_clk_50m,
    input  wire                       audio_clk_12m288,
    input  wire                       rst_n,

    output wire                       dac_bclk,
    output wire                       dac_lrck,
    output wire                       dac_din,
    output wire                       pa_en,
    output wire                       led
);

    wire        note_on;
    wire        note_off;
    wire [31:0] e4_phase_inc;
    wire        voice_active;

    reg [31:0] led_count;
    reg        led_reg;

    assign note_off = 1'b0;

    note_phase_rom u_note_phase_rom (
        .e4_phase_inc(e4_phase_inc)
    );

    test_tone_trigger u_test_tone_trigger (
        .clk  (audio_clk_12m288),
        .rst_n(rst_n),
        .note_on(note_on)
    );

    minimal_audio_output #(
        .SAMPLE_DIV(SAMPLE_DIV)
    ) u_minimal_audio_output (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .phase_inc    (e4_phase_inc),
        .sample_tick  (),
        .voice_active (voice_active),
        .pcm16_valid  (),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    // 50 MHz 系统时钟心跳指示
    always @(posedge sys_clk_50m) begin
        if (!rst_n) begin
            led_count <= 32'd0;
            led_reg   <= 1'b0;
        end
        else if (led_count == LED_HALF_PERIOD - 1) begin
            led_count <= 32'd0;
            led_reg   <= ~led_reg;
        end
        else begin
            led_count <= led_count + 1'b1;
        end
    end

    assign led   = led_reg;
    assign pa_en = voice_active;

endmodule