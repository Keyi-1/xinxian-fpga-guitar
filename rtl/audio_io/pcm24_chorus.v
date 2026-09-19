`include "../config/guitar_config.vh"

// Mono chorus using a continuously-filled short delay line, triangle LFO and
// a click-free dry/effect crossfade.  The memory is small enough for LUT RAM
// and can be mapped to B-SRAM by synthesis if desired.
module pcm24_chorus #(
    parameter integer BUFFER_BITS = 7,
    parameter integer BASE_DELAY = `CHORUS_BASE_DELAY_SAMPLES,
    parameter integer MOD_DEPTH = `CHORUS_MOD_DEPTH_SAMPLES,
    parameter integer LFO_HOLD_SAMPLES = `CHORUS_LFO_HOLD_SAMPLES,
    parameter integer BLEND_SAMPLES = `FX_BLEND_SAMPLES
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid_in,
    input  wire signed [23:0] pcm_in,
    input  wire               chorus_enable,

    output reg                sample_valid,
    output reg signed [23:0]  pcm_out,
    output reg [8:0]          effect_blend,
    output wire               effect_busy,
    output reg [7:0]          lfo_position
);

    localparam integer BUFFER_DEPTH = (1 << BUFFER_BITS);
    localparam integer MAX_DELAY = BASE_DELAY + MOD_DEPTH;
    localparam integer BLEND_STEP =
        (256 + BLEND_SAMPLES - 1) / BLEND_SAMPLES;

    reg signed [23:0] delay_mem [0:BUFFER_DEPTH-1];
    reg [BUFFER_BITS-1:0] write_ptr;
    reg [BUFFER_BITS:0] fill_count;
    reg [15:0] lfo_hold_count;
    reg lfo_direction_up;

    reg [BUFFER_BITS-1:0] read_ptr;
    reg signed [23:0] delayed_sample;
    reg signed [24:0] chorus_sum;
    reg signed [23:0] chorus_sample;
    reg [9:0] dry_weight;
    reg signed [34:0] dry_product;
    reg signed [34:0] effect_product;
    reg signed [34:0] blended_sample;

    assign effect_busy = chorus_enable ? (effect_blend < 9'd256) :
                                        (effect_blend != 9'd0);

    function signed [23:0] saturate_pcm24;
        input signed [34:0] value;
        begin
            if (value > 35'sd8388607)
                saturate_pcm24 = 24'sh7fffff;
            else if (value < -35'sd8388608)
                saturate_pcm24 = 24'sh800000;
            else
                saturate_pcm24 = value[23:0];
        end
    endfunction

    always @* begin
        read_ptr = write_ptr - BASE_DELAY - lfo_position;
        if (fill_count < MAX_DELAY)
            delayed_sample = 24'sd0;
        else
            delayed_sample = delay_mem[read_ptr];

        chorus_sum = ($signed(pcm_in) >>> 1) +
                     ($signed(delayed_sample) >>> 1);
        chorus_sample = chorus_sum[23:0];
        dry_weight = 10'd256 - {1'b0, effect_blend};
        dry_product = $signed(pcm_in) * $signed({1'b0, dry_weight});
        effect_product = $signed(chorus_sample) *
                         $signed({1'b0, effect_blend});
        blended_sample = (dry_product + effect_product) >>> 8;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            pcm_out <= 24'sd0;
            effect_blend <= 9'd0;
            write_ptr <= {BUFFER_BITS{1'b0}};
            fill_count <= {(BUFFER_BITS + 1){1'b0}};
            lfo_hold_count <= 16'd0;
            lfo_position <= 8'd0;
            lfo_direction_up <= 1'b1;
        end
        else begin
            sample_valid <= sample_valid_in;
            if (sample_valid_in) begin
                pcm_out <= saturate_pcm24(blended_sample);
                delay_mem[write_ptr] <= pcm_in;
                write_ptr <= write_ptr + 1'b1;
                if (fill_count < MAX_DELAY)
                    fill_count <= fill_count + 1'b1;

                if (chorus_enable) begin
                    if (effect_blend + BLEND_STEP >= 9'd256)
                        effect_blend <= 9'd256;
                    else
                        effect_blend <= effect_blend + BLEND_STEP;
                end
                else begin
                    if (effect_blend <= BLEND_STEP)
                        effect_blend <= 9'd0;
                    else
                        effect_blend <= effect_blend - BLEND_STEP;
                end

                if (lfo_hold_count == LFO_HOLD_SAMPLES - 1) begin
                    lfo_hold_count <= 16'd0;
                    if (lfo_direction_up) begin
                        if (lfo_position >= MOD_DEPTH) begin
                            lfo_direction_up <= 1'b0;
                            if (lfo_position != 0)
                                lfo_position <= lfo_position - 1'b1;
                        end
                        else
                            lfo_position <= lfo_position + 1'b1;
                    end
                    else begin
                        if (lfo_position == 0) begin
                            lfo_direction_up <= 1'b1;
                            lfo_position <= 8'd1;
                        end
                        else
                            lfo_position <= lfo_position - 1'b1;
                    end
                end
                else
                    lfo_hold_count <= lfo_hold_count + 1'b1;
            end
        end
    end

endmodule
