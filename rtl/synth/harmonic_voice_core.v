`include "../config/guitar_config.vh"

// One scheduled harmonic engine per voice. It completes HARMONICS logical
// components between two 48 kHz sample enables and emits one saturated PCM24.
module harmonic_voice_core #(
    parameter integer HARMONICS = `HARMONICS_MAX
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         sample_ce,
    input  wire                         note_on,
    input  wire                         note_off,
    input  wire [1:0]                   velocity_level,
    input  wire [`PHASE_ACC_BITS-1:0]   phase_inc,
    input  wire [8:0]                   timbre_blend,
    input  wire                         sustain_enable,

    output reg                          sample_valid,
    output reg signed [23:0]            pcm_out,
    output wire [`ENV_LEVEL_BITS-1:0]   env_level,
    output wire                         active,
    output reg                          busy,
    output reg                          deadline_miss
);

    reg [`PHASE_ACC_BITS-1:0] phase_acc;
    reg [`PHASE_ACC_BITS-1:0] phase_latched;
    reg [5:0] harmonic_index;
    reg signed [39:0] accumulator;

    reg signed [`SINE_LUT_VALUE_BITS-1:0] sine_lut [0:`SINE_LUT_SIZE-1];
    reg signed [15:0] harmonic_gain [0:HARMONICS-1];
    reg signed [15:0] harmonic_gain_rock [0:HARMONICS-1];
    reg signed [15:0] harmonic_decay [0:HARMONICS-1];
    reg signed [15:0] harmonic_decay_rock [0:HARMONICS-1];
    reg signed [15:0] harmonic_amplitude [0:HARMONICS-1];
    reg signed [15:0] harmonic_amplitude_rock [0:HARMONICS-1];
    reg [1:0] velocity_latched;

    wire [`ENV_LEVEL_BITS-1:0] envelope_level;
    wire envelope_active;

    reg [37:0] harmonic_phase_wide;
    reg [`PHASE_ACC_BITS-1:0] harmonic_phase;
    reg [`SINE_LUT_ADDR_BITS-1:0] lut_addr;
    reg signed [16:0] amplitude_difference;
    reg signed [26:0] blend_product;
    reg signed [17:0] blended_amplitude_wide;
    reg signed [15:0] blended_amplitude;
    reg signed [31:0] sine_amplitude_product;
    reg signed [15:0] scaled_sine;
    reg signed [31:0] envelope_product;
    reg signed [39:0] component_pcm;
    reg signed [39:0] accumulator_next;
    reg signed [31:0] decay_product;
    reg signed [31:0] decay_product_rock;
    integer i;

    initial begin
        $readmemh("../../mem/sine_lut.mem", sine_lut);
        $readmemh("../../mem/harmonic_gain_default.mem", harmonic_gain);
        $readmemh("../../mem/harmonic_gain_rock.mem", harmonic_gain_rock);
        $readmemh("../../mem/harmonic_decay_default.mem", harmonic_decay);
        $readmemh("../../mem/harmonic_decay_rock.mem", harmonic_decay_rock);
    end

    voice_envelope u_voice_envelope (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_ce     (sample_ce),
        .note_on       (note_on),
        .note_off      (note_off),
        .velocity_level(velocity_level),
        .sustain_enable(sustain_enable),
        .env_level     (envelope_level),
        .active        (envelope_active)
    );

    assign env_level = envelope_level;
    assign active = envelope_active;

    function signed [23:0] saturate_pcm24;
        input signed [39:0] value;
        begin
            if (value > 40'sd8388607)
                saturate_pcm24 = 24'sh7fffff;
            else if (value < -40'sd8388608)
                saturate_pcm24 = 24'sh800000;
            else
                saturate_pcm24 = value[23:0];
        end
    endfunction

    function signed [15:0] velocity_scaled_gain;
        input signed [15:0] gain;
        input integer index;
        input [1:0] velocity;
        input rock_profile;
        reg signed [31:0] scaled;
        begin
            if (index < 4) begin
                case (velocity)
                    2'd0: scaled = gain - (gain >>> 2);
                    2'd1: scaled = gain - (gain >>> 3);
                    2'd2: scaled = gain - (gain >>> 4);
                    default: scaled = gain;
                endcase
            end
            else begin
                case (velocity)
                    2'd0: scaled = gain >>> 2;
                    2'd1: scaled = gain >>> 1;
                    2'd2: scaled = rock_profile ? gain :
                            (gain - (gain >>> 2));
                    default: scaled = rock_profile ?
                                      (gain + (gain >>> 2)) : gain;
                endcase
            end
            if (scaled > 32767)
                velocity_scaled_gain = 16'sh7fff;
            else if (scaled < 0)
                velocity_scaled_gain = 16'sd0;
            else
                velocity_scaled_gain = scaled[15:0];
        end
    endfunction

    function signed [15:0] velocity_decay_coefficient;
        input signed [15:0] base_coefficient;
        input [1:0] velocity;
        reg signed [16:0] adjusted;
        begin
            adjusted = $signed({1'b0, base_coefficient}) + velocity;
            if (adjusted > 17'sd32767)
                velocity_decay_coefficient = 16'sh7fff;
            else
                velocity_decay_coefficient = adjusted[15:0];
        end
    endfunction

    always @* begin
        harmonic_phase_wide = phase_latched * (harmonic_index + 1'b1);
        harmonic_phase = harmonic_phase_wide[`PHASE_ACC_BITS-1:0];
        lut_addr = harmonic_phase[`PHASE_ACC_BITS-1 -: `SINE_LUT_ADDR_BITS];

        amplitude_difference =
            $signed(harmonic_amplitude_rock[harmonic_index]) -
            $signed(harmonic_amplitude[harmonic_index]);
        blend_product = amplitude_difference *
                        $signed({1'b0, timbre_blend});
        blended_amplitude_wide =
            $signed({{2{harmonic_amplitude[harmonic_index][15]}},
                     harmonic_amplitude[harmonic_index]}) +
            (blend_product >>> 8);
        blended_amplitude = blended_amplitude_wide[15:0];

        sine_amplitude_product = $signed(sine_lut[lut_addr]) *
                                 $signed(blended_amplitude);
        scaled_sine = sine_amplitude_product >>> 15;
        envelope_product = $signed(scaled_sine) * $signed(envelope_level);
        component_pcm = envelope_product >>> 7;
        accumulator_next = accumulator + component_pcm;
        decay_product = $signed(harmonic_amplitude[harmonic_index]) *
                        $signed(velocity_decay_coefficient(
                            harmonic_decay[harmonic_index],
                            velocity_latched));
        decay_product_rock =
            $signed(harmonic_amplitude_rock[harmonic_index]) *
            $signed(velocity_decay_coefficient(
                harmonic_decay_rock[harmonic_index],
                velocity_latched));
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            phase_acc     <= 0;
            phase_latched <= 0;
            harmonic_index <= 0;
            accumulator   <= 0;
            sample_valid  <= 1'b0;
            pcm_out       <= 24'sd0;
            busy          <= 1'b0;
            deadline_miss <= 1'b0;
            velocity_latched <= 2'd0;
            for (i = 0; i < HARMONICS; i = i + 1) begin
                harmonic_amplitude[i] <= 16'sd0;
                harmonic_amplitude_rock[i] <= 16'sd0;
            end
        end
        else begin
            sample_valid <= 1'b0;

            if (sample_ce) begin
                if (busy)
                    deadline_miss <= 1'b1;
                else begin
                    phase_acc     <= phase_acc + phase_inc;
                    phase_latched <= phase_acc + phase_inc;
                    harmonic_index <= 0;
                    accumulator   <= 0;
                    busy          <= 1'b1;

                    if (note_on) begin
                        velocity_latched <= velocity_level;
                        for (i = 0; i < HARMONICS; i = i + 1) begin
                            harmonic_amplitude[i] <= velocity_scaled_gain(
                                harmonic_gain[i], i, velocity_level, 1'b0);
                            harmonic_amplitude_rock[i] <=
                                velocity_scaled_gain(harmonic_gain_rock[i], i,
                                                     velocity_level, 1'b1);
                        end
                    end
                end
            end

            if (busy) begin
                harmonic_amplitude[harmonic_index] <= decay_product >>> 15;
                harmonic_amplitude_rock[harmonic_index] <=
                    decay_product_rock >>> 15;

                if (harmonic_index == HARMONICS - 1) begin
                    pcm_out      <= saturate_pcm24(accumulator_next);
                    sample_valid <= 1'b1;
                    busy         <= 1'b0;
                end
                else begin
                    accumulator <= accumulator_next;
                    harmonic_index <= harmonic_index + 1'b1;
                end
            end
        end
    end

endmodule
