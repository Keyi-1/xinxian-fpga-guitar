`include "guitar_config.vh"

// Smooths one phase increment at the audio sample rate.
// When voice_active is low, a new target is selected immediately.
// When voice_active is high, the current value approaches the target
// monotonically over SLIDE_SAMPLES sample enables.
module phase_slide_smoother #(
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_ce,
    input  wire        note_on,
    input  wire        voice_active,
    input  wire [31:0] target_phase_inc,

    output reg  [31:0] phase_inc,
    output reg         busy
);

    reg [32:0] difference;
    reg [32:0] step_size;
    reg [32:0] next_phase_calc;
    reg [32:0] next_phase_latched;
    reg [31:0] slide_count;
    reg [31:0] slide_target;
    reg [32:0] slide_step;

    always @* begin
        difference = 33'd0;
        step_size  = 33'd1;

        if (target_phase_inc >= phase_inc)
            difference = {1'b0, target_phase_inc} - {1'b0, phase_inc};
        else
            difference = {1'b0, phase_inc} - {1'b0, target_phase_inc};

        if (difference != 0) begin
            step_size = (difference + SLIDE_SAMPLES - 1)
                        / SLIDE_SAMPLES;
            if (step_size == 0)
                step_size = 33'd1;
        end

        if (target_phase_inc > phase_inc) begin
            if ({1'b0, phase_inc} + step_size >= {1'b0, target_phase_inc})
                next_phase_calc = {1'b0, target_phase_inc};
            else
                next_phase_calc = {1'b0, phase_inc} + step_size;
        end
        else if (target_phase_inc < phase_inc) begin
            if ({1'b0, phase_inc} <= {1'b0, target_phase_inc} + step_size)
                next_phase_calc = {1'b0, target_phase_inc};
            else
                next_phase_calc = {1'b0, phase_inc} - step_size;
        end
        else begin
            next_phase_calc = {1'b0, phase_inc};
        end

        if (target_phase_inc > phase_inc) begin
            if ({1'b0, phase_inc} + slide_step >= {1'b0, target_phase_inc})
                next_phase_latched = {1'b0, target_phase_inc};
            else
                next_phase_latched = {1'b0, phase_inc} + slide_step;
        end
        else if (target_phase_inc < phase_inc) begin
            if ({1'b0, phase_inc} <= {1'b0, target_phase_inc} + slide_step)
                next_phase_latched = {1'b0, target_phase_inc};
            else
                next_phase_latched = {1'b0, phase_inc} - slide_step;
        end
        else begin
            next_phase_latched = {1'b0, phase_inc};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_inc <= 32'd0;
            busy      <= 1'b0;
            slide_count <= 32'd0;
            slide_target <= 32'd0;
            slide_step <= 33'd1;
        end
        else if (sample_ce) begin
            if (note_on) begin
                phase_inc <= target_phase_inc;
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_phase_inc;
            end
            else if (!voice_active) begin
                phase_inc <= target_phase_inc;
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_phase_inc;
            end
            else if (phase_inc == target_phase_inc) begin
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_phase_inc;
            end
            else begin
                // Start or retargeting a slide locks a fixed step size.
                if (!busy || (slide_target != target_phase_inc)) begin
                    phase_inc <= next_phase_calc[31:0];
                    slide_target <= target_phase_inc;
                    slide_step <= step_size;
                    slide_count <= 32'd1;

                    if ((SLIDE_SAMPLES <= 1) ||
                        (next_phase_calc[31:0] == target_phase_inc))
                        busy <= 1'b0;
                    else
                        busy <= 1'b1;
                end
                else begin
                    phase_inc <= next_phase_latched[31:0];

                    if ((slide_count >= SLIDE_SAMPLES - 1) ||
                        (next_phase_latched[31:0] == target_phase_inc)) begin
                        phase_inc <= target_phase_inc;
                        busy      <= 1'b0;
                        slide_count <= 32'd0;
                    end
                    else begin
                        slide_count <= slide_count + 1;
                        busy        <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
