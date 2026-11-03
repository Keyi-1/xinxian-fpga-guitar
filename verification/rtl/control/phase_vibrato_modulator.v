`include "../config/guitar_config.vh"

// Triangle-LFO pitch modulation around a smoothed base phase increment.
// DEPTH_Q15=380 is approximately +/-20 cents.  Resetting the LFO to its
// zero-crossing makes a newly-entered vibrato start without a pitch step.
module phase_vibrato_modulator #(
    parameter [31:0] LFO_PHASE_INC = `VIBRATO_LFO_PHASE_INC,
    parameter [15:0] DEPTH_Q15     = `VIBRATO_DEPTH_Q15
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_ce,
    input  wire        enable,
    input  wire [31:0] base_phase_inc,
    output reg  [31:0] phase_inc
);

    reg [31:0] lfo_phase;
    reg signed [16:0] triangle_q15;
    reg signed [33:0] lfo_scale_q15;
    reg signed [65:0] phase_delta_wide;
    reg signed [33:0] phase_adjusted;

    always @* begin
        if (lfo_phase[31])
            triangle_q15 = 17'sd32767 -
                           $signed({1'b0, lfo_phase[30:15]});
        else
            triangle_q15 = -17'sd32768 +
                           $signed({1'b0, lfo_phase[30:15]});

        lfo_scale_q15 = (triangle_q15 * $signed({1'b0, DEPTH_Q15})) >>> 15;
        phase_delta_wide = $signed({1'b0, base_phase_inc}) * lfo_scale_q15;
        phase_adjusted = $signed({1'b0, base_phase_inc}) +
                         (phase_delta_wide >>> 15);

        if (phase_adjusted < 0)
            phase_inc = 32'd0;
        else if (phase_adjusted > 34'sd4294967295)
            phase_inc = 32'hffffffff;
        else
            phase_inc = phase_adjusted[31:0];
    end

    always @(posedge clk) begin
        if (!rst_n)
            lfo_phase <= 32'h40000000;
        else if (sample_ce) begin
            if (enable)
                lfo_phase <= lfo_phase + LFO_PHASE_INC;
            else
                lfo_phase <= 32'h40000000;
        end
    end

endmodule
