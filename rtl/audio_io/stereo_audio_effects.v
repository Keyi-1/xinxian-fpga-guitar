`include "../config/guitar_config.vh"
// Separate delay/effect state per channel preserves the verified hard stereo.
module stereo_audio_effects #(parameter integer ENABLE = 0) (
    input wire clk, rst_n, sample_valid_in,
    input wire signed [23:0] pcm_left, pcm_right,
    input wire [1:0] drive_level,
    input wire [8:0] timbre_blend,
    input wire chorus_enable, reverb_enable,
    output wire sample_valid,
    output wire signed [23:0] left_out, right_out,
    output wire [8:0] chorus_blend, reverb_blend,
    output wire chorus_busy, reverb_busy
);
    generate if (ENABLE == 0) begin : g_bypass
        assign sample_valid = sample_valid_in;
        assign left_out = pcm_left;
        assign right_out = pcm_right;
        assign chorus_blend = 0; assign reverb_blend = 0;
        assign chorus_busy = 0; assign reverb_busy = 0;
    end else begin : g_effects
        wire [47:0] pcm_input = {pcm_right,pcm_left};
        wire [47:0] pcm_output;
        wire [1:0] valid;
        genvar c;
        for (c = 0; c < 2; c = c + 1) begin : channel
            wire clipped_valid, chorus_valid;
            wire signed [23:0] clipped_pcm, chorus_pcm;
            wire [8:0] cb, rb;
            wire cbusy, rbusy;
            pcm24_rock_soft_clip u_clip (
                .clk(clk), .rst_n(rst_n), .sample_valid_in(sample_valid_in),
                .pcm_in(pcm_input[c*24 +: 24]), .drive_level(drive_level),
                .timbre_blend(timbre_blend), .sample_valid(clipped_valid),
                .pcm_out(clipped_pcm)
            );
            pcm24_chorus u_chorus (
                .clk(clk), .rst_n(rst_n), .sample_valid_in(clipped_valid),
                .pcm_in(clipped_pcm), .chorus_enable(chorus_enable),
                .sample_valid(chorus_valid), .pcm_out(chorus_pcm),
                .effect_blend(cb), .effect_busy(cbusy), .lfo_position()
            );
            pcm24_reverb u_reverb (
                .clk(clk), .rst_n(rst_n), .sample_valid_in(chorus_valid),
                .pcm_in(chorus_pcm), .reverb_enable(reverb_enable),
                .sample_valid(valid[c]), .pcm_out(pcm_output[c*24 +: 24]),
                .effect_blend(rb), .effect_busy(rbusy)
            );
            if (c == 0) begin : status
                assign chorus_blend = cb; assign reverb_blend = rb;
                assign chorus_busy = cbusy; assign reverb_busy = rbusy;
            end
        end
        assign sample_valid = valid[0];
        assign left_out = pcm_output[23:0];
        assign right_out = pcm_output[47:24];
    end endgenerate
endmodule
