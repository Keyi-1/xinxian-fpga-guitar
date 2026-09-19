`include "../config/guitar_config.vh"

// Three-line cross-feedback delay network.  Every feedback edge has a fixed
// gain of 1/2, so the loop gain is bounded below unity.  The exact-size arrays
// are intended for block-RAM inference and do not require DDR memory.
module pcm24_reverb #(
    parameter integer DELAY_A = `REVERB_DELAY_A_SAMPLES,
    parameter integer DELAY_B = `REVERB_DELAY_B_SAMPLES,
    parameter integer DELAY_C = `REVERB_DELAY_C_SAMPLES,
    parameter integer BLEND_SAMPLES = `FX_BLEND_SAMPLES
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid_in,
    input  wire signed [23:0] pcm_in,
    input  wire               reverb_enable,

    output reg                sample_valid,
    output reg signed [23:0]  pcm_out,
    output reg [8:0]          effect_blend,
    output wire               effect_busy
);

    localparam integer BLEND_STEP =
        (256 + BLEND_SAMPLES - 1) / BLEND_SAMPLES;

    reg signed [23:0] delay_a [0:DELAY_A-1];
    reg signed [23:0] delay_b [0:DELAY_B-1];
    reg signed [23:0] delay_c [0:DELAY_C-1];
    reg [15:0] ptr_a;
    reg [15:0] ptr_b;
    reg [15:0] ptr_c;
    reg [15:0] fill_a;
    reg [15:0] fill_b;
    reg [15:0] fill_c;

    reg signed [23:0] tap_a;
    reg signed [23:0] tap_b;
    reg signed [23:0] tap_c;
    reg signed [24:0] write_a_wide;
    reg signed [24:0] write_b_wide;
    reg signed [24:0] write_c_wide;
    reg signed [23:0] write_a;
    reg signed [23:0] write_b;
    reg signed [23:0] write_c;
    reg signed [26:0] reverb_wide;
    reg signed [23:0] reverb_sample;
    reg [9:0] dry_weight;
    reg signed [34:0] dry_product;
    reg signed [34:0] effect_product;
    reg signed [34:0] blended_sample;

    assign effect_busy = reverb_enable ? (effect_blend < 9'd256) :
                                        (effect_blend != 9'd0);

    function signed [23:0] saturate25;
        input signed [24:0] value;
        begin
            if (value > 25'sd8388607)
                saturate25 = 24'sh7fffff;
            else if (value < -25'sd8388608)
                saturate25 = 24'sh800000;
            else
                saturate25 = value[23:0];
        end
    endfunction

    function signed [23:0] saturate35;
        input signed [34:0] value;
        begin
            if (value > 35'sd8388607)
                saturate35 = 24'sh7fffff;
            else if (value < -35'sd8388608)
                saturate35 = 24'sh800000;
            else
                saturate35 = value[23:0];
        end
    endfunction

    always @* begin
        tap_a = (fill_a < DELAY_A) ? 24'sd0 : delay_a[ptr_a];
        tap_b = (fill_b < DELAY_B) ? 24'sd0 : delay_b[ptr_b];
        tap_c = (fill_c < DELAY_C) ? 24'sd0 : delay_c[ptr_c];

        write_a_wide = $signed({pcm_in[23], pcm_in}) +
                       ($signed({tap_b[23], tap_b}) >>> 1);
        write_b_wide = $signed({pcm_in[23], pcm_in}) +
                       ($signed({tap_c[23], tap_c}) >>> 1);
        write_c_wide = $signed({pcm_in[23], pcm_in}) +
                       ($signed({tap_a[23], tap_a}) >>> 1);
        write_a = saturate25(write_a_wide);
        write_b = saturate25(write_b_wide);
        write_c = saturate25(write_c_wide);

        reverb_wide = ($signed({{3{pcm_in[23]}}, pcm_in}) >>> 1) +
                      ($signed({{3{tap_a[23]}}, tap_a}) >>> 3) +
                      ($signed({{3{tap_b[23]}}, tap_b}) >>> 3) +
                      ($signed({{3{tap_c[23]}}, tap_c}) >>> 3);
        reverb_sample = reverb_wide[23:0];
        dry_weight = 10'd256 - {1'b0, effect_blend};
        dry_product = $signed(pcm_in) * $signed({1'b0, dry_weight});
        effect_product = $signed(reverb_sample) *
                         $signed({1'b0, effect_blend});
        blended_sample = (dry_product + effect_product) >>> 8;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            pcm_out <= 24'sd0;
            effect_blend <= 9'd0;
            ptr_a <= 16'd0;
            ptr_b <= 16'd0;
            ptr_c <= 16'd0;
            fill_a <= 16'd0;
            fill_b <= 16'd0;
            fill_c <= 16'd0;
        end
        else begin
            sample_valid <= sample_valid_in;
            if (sample_valid_in) begin
                pcm_out <= saturate35(blended_sample);
                delay_a[ptr_a] <= write_a;
                delay_b[ptr_b] <= write_b;
                delay_c[ptr_c] <= write_c;

                if (ptr_a == DELAY_A - 1) ptr_a <= 16'd0;
                else ptr_a <= ptr_a + 1'b1;
                if (ptr_b == DELAY_B - 1) ptr_b <= 16'd0;
                else ptr_b <= ptr_b + 1'b1;
                if (ptr_c == DELAY_C - 1) ptr_c <= 16'd0;
                else ptr_c <= ptr_c + 1'b1;

                if (fill_a < DELAY_A) fill_a <= fill_a + 1'b1;
                if (fill_b < DELAY_B) fill_b <= fill_b + 1'b1;
                if (fill_c < DELAY_C) fill_c <= fill_c + 1'b1;

                if (reverb_enable) begin
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
            end
        end
    end

endmodule
