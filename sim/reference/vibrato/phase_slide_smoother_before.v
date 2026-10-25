`include "../config/guitar_config.vh"

// Smooths one phase increment at the audio sample rate.
// When voice_active is low, a new target is selected immediately.
// When voice_active is high, the current value approaches the target
// monotonically over SLIDE_SAMPLES sample enables.
module vibrato_before_phase_slide_smoother #(
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer PHASE_VALUE_BITS = 32
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

    // Factor powers of two out of the constant divisor before synthesis.
    // floor(N / (2^k*d)) == floor((N >> k) / d), including the existing
    // ceil numerator N=difference+SLIDE_SAMPLES-1. For 960, divide 27 bits
    // by 15 instead of presenting a full 33-bit divide by 960.
    function integer divisor_shift;
        input integer divisor;
        integer reduced, bit_index;
        begin
            reduced = divisor;
            divisor_shift = 0;
            for (bit_index = 0; bit_index < 31; bit_index = bit_index + 1)
                if (reduced > 0 && (reduced & 1) == 0) begin
                    divisor_shift = divisor_shift + 1;
                    reduced = reduced >> 1;
                end
        end
    endfunction
    localparam integer DIV_POW2_SHIFT = divisor_shift(SLIDE_SAMPLES);
    localparam integer DIV_ODD = SLIDE_SAMPLES >> DIV_POW2_SHIFT;

    function integer value_bits;
        input integer value;
        integer remaining, k;
        begin
            value_bits = 0;
            remaining = value;
            for (k = 0; k < 31; k = k + 1)
                if (remaining > 0) begin
                    value_bits = value_bits + 1;
                    remaining = remaining >> 1;
                end
        end
    endfunction
    localparam integer N_BITS = value_bits(SLIDE_SAMPLES - 1);
    localparam integer ROUND_BITS = ((PHASE_VALUE_BITS > N_BITS) ?
                                     PHASE_VALUE_BITS : N_BITS) + 1;
    localparam integer COUNT_BITS = (N_BITS < 1) ? 1 : N_BITS;
    localparam [ROUND_BITS-DIV_POW2_SHIFT-1:0] DIV_ODD_VALUE = DIV_ODD;
    // Width constrains the value range, not the DDS resolution. The board
    // uses all 26 meaningful bits of its exact 32-bit ROM increments.
    wire [PHASE_VALUE_BITS-1:0] target_value = target_phase_inc[PHASE_VALUE_BITS-1:0];
    wire [PHASE_VALUE_BITS-1:0] current_phase = phase_inc[PHASE_VALUE_BITS-1:0];

    reg [PHASE_VALUE_BITS-1:0] difference;
    reg [ROUND_BITS-1:0] rounded_difference;
    reg [ROUND_BITS-DIV_POW2_SHIFT-1:0] reduced_difference;
    reg [PHASE_VALUE_BITS:0] step_size;
    reg [PHASE_VALUE_BITS:0] next_phase_calc;
    reg [PHASE_VALUE_BITS:0] next_phase_latched;
    reg [COUNT_BITS-1:0] slide_count;
    reg [PHASE_VALUE_BITS-1:0] slide_target;
    reg [PHASE_VALUE_BITS:0] slide_step;

    always @* begin
        difference = 33'd0;
        rounded_difference = 33'd0;
        reduced_difference = 0;
        step_size  = 33'd1;

        if (target_value >= current_phase)
            difference = target_value - current_phase;
        else
            difference = current_phase - target_value;

        if (difference != 0) begin
            rounded_difference = difference + SLIDE_SAMPLES - 1;
            reduced_difference = rounded_difference[ROUND_BITS-1:DIV_POW2_SHIFT];
            step_size = reduced_difference / DIV_ODD_VALUE;
            if (step_size == 0)
                step_size = 33'd1;
        end

        if (target_value > current_phase) begin
            if ({1'b0, current_phase} + step_size >= {1'b0, target_value})
                next_phase_calc = {1'b0, target_value};
            else
                next_phase_calc = {1'b0, current_phase} + step_size;
        end
        else if (target_value < current_phase) begin
            if ({1'b0, current_phase} <= {1'b0, target_value} + step_size)
                next_phase_calc = {1'b0, target_value};
            else
                next_phase_calc = {1'b0, current_phase} - step_size;
        end
        else begin
            next_phase_calc = {1'b0, current_phase};
        end

        if (target_value > current_phase) begin
            if ({1'b0, current_phase} + slide_step >= {1'b0, target_value})
                next_phase_latched = {1'b0, target_value};
            else
                next_phase_latched = {1'b0, current_phase} + slide_step;
        end
        else if (target_value < current_phase) begin
            if ({1'b0, current_phase} <= {1'b0, target_value} + slide_step)
                next_phase_latched = {1'b0, target_value};
            else
                next_phase_latched = {1'b0, current_phase} - slide_step;
        end
        else begin
            next_phase_latched = {1'b0, current_phase};
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
                phase_inc <= target_value;
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_value;
            end
            else if (!voice_active) begin
                phase_inc <= target_value;
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_value;
            end
            else if (current_phase == target_value) begin
                busy      <= 1'b0;
                slide_count <= 32'd0;
                slide_target <= target_value;
            end
            else begin
                // Start or retargeting a slide locks a fixed step size.
                if (!busy || (slide_target != target_value)) begin
                    phase_inc <= next_phase_calc[PHASE_VALUE_BITS-1:0];
                    slide_target <= target_value;
                    slide_step <= step_size;
                    slide_count <= 32'd1;

                    if ((SLIDE_SAMPLES <= 1) ||
                        (next_phase_calc[PHASE_VALUE_BITS-1:0] == target_value))
                        busy <= 1'b0;
                    else
                        busy <= 1'b1;
                end
                else begin
                    phase_inc <= next_phase_latched[PHASE_VALUE_BITS-1:0];

                    if ((slide_count >= SLIDE_SAMPLES - 1) ||
                        (next_phase_latched[PHASE_VALUE_BITS-1:0] == target_value)) begin
                        phase_inc <= target_value;
                        busy      <= 1'b0;
                        slide_count <= 32'd0;
                    end
                    else begin
                        slide_count <= slide_count + 1'b1;
                        busy        <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
