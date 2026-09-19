`include "../config/guitar_config.vh"

module voice_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV
) (
    input  wire                                  clk_audio_ref,
    input  wire                                  rst_n,
    input  wire                                  note_on,
    input  wire                                  note_off,
    input  wire [1:0]                            velocity_level,
    input  wire [`PHASE_ACC_BITS-1:0]            phase_inc,

    output wire                                  sample_tick,
    output reg                                   sample_valid,
    output reg  signed [`INTERNAL_PCM_BITS-1:0]  pcm_out,
    output wire [`ENV_LEVEL_BITS-1:0]            env_level,
    output wire                                  active
);

    wire signed [`SINE_LUT_VALUE_BITS-1:0] nco_sample;
    wire nco_sample_valid;

    wire [`ENV_LEVEL_BITS-1:0] envelope_level;
    wire envelope_active;

    wire signed [15:0] env_gain;
    wire signed [31:0] pcm_product;

    assign env_gain    = envelope_level;
    assign pcm_product = $signed(nco_sample) * $signed(env_gain);

    sample_tick_gen #(
        .DIVISOR(SAMPLE_DIV)
    ) u_sample_tick_gen (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick)
    );

    sine_nco u_sine_nco (
        .clk         (clk_audio_ref),
        .rst_n       (rst_n),
        .sample_ce   (sample_tick),
        .phase_inc   (phase_inc),
        .sample_out  (nco_sample),
        .sample_valid(nco_sample_valid)
    );

    voice_envelope u_voice_envelope (
        .clk       (clk_audio_ref),
        .rst_n     (rst_n),
        .sample_ce (sample_tick),
        .note_on   (note_on),
        .note_off  (note_off),
        .velocity_level(velocity_level),
        .sustain_enable(1'b0),
        .env_level (envelope_level),
        .active    (envelope_active)
    );

    assign env_level = envelope_level;
    assign active    = envelope_active;

    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            pcm_out      <= {`INTERNAL_PCM_BITS{1'b0}};
        end
        else begin
            sample_valid <= nco_sample_valid;

            if (nco_sample_valid) begin
                // Q1.15 包络增益乘以 16-bit 正弦样本
                pcm_out <= pcm_product >>> 7;
            end
        end
    end

endmodule
