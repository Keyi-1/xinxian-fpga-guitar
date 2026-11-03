`include "../config/guitar_config.vh"

module minimal_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV
) (
    input  wire                                  clk_audio_ref,
    input  wire                                  rst_n,
    input  wire                                  voice_enable,
    input  wire [`PHASE_ACC_BITS-1:0]            phase_inc,

    output wire                                  sample_tick,
    output reg                                  sample_valid,
    output reg  signed [`INTERNAL_PCM_BITS-1:0]  pcm_out
);

    wire signed [`SINE_LUT_VALUE_BITS-1:0] nco_sample;
    wire nco_sample_valid;

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

    always @(posedge clk_audio_ref) begin
    if (!rst_n) begin
        pcm_out     <= {`INTERNAL_PCM_BITS{1'b0}};
        sample_valid <= 1'b0;
    end
    else begin
        sample_valid <= nco_sample_valid;

        if (nco_sample_valid) begin
            if (voice_enable) begin
                pcm_out <= {{8{nco_sample[15]}}, nco_sample};
            end
            else begin
                pcm_out <= {`INTERNAL_PCM_BITS{1'b0}};
            end
        end
    end
end

endmodule