// FULL effects retain the accepted narrow stereo and the common piano room.
module piano_stereo_effects #(parameter integer ROOM_ENABLE=1)(
    input wire clk,rst_n,sample_valid_in,
    input wire signed [23:0] left_in,right_in,
    input wire [1:0] drive_level,
    input wire [8:0] timbre_blend,
    input wire chorus_enable,room_enable,
    output wire sample_valid,
    output wire signed [23:0] left_out,right_out,
    output wire [8:0] chorus_blend,reverb_blend,
    output wire chorus_busy,reverb_busy
);
    wire [47:0] pcm={right_in,left_in};
    wire [47:0] clipped_pcm;
    wire [1:0] clip_valid;
    wire chorus_valid;
    wire signed [23:0] chorus_l,chorus_r;
    genvar c;
    generate for(c=0;c<2;c=c+1)begin : channel
        pcm24_rock_soft_clip u_clip(
            .clk(clk),.rst_n(rst_n),.sample_valid_in(sample_valid_in),
            .pcm_in(pcm[c*24+:24]),.drive_level(drive_level),.timbre_blend(timbre_blend),
            .sample_valid(clip_valid[c]),.pcm_out(clipped_pcm[c*24+:24]));
    end endgenerate
    piano_stereo_chorus u_chorus(
        .clk(clk),.rst_n(rst_n),.sample_valid_in(clip_valid[0]),
        .left_in(clipped_pcm[23:0]),.right_in(clipped_pcm[47:24]),
        .chorus_enable(chorus_enable),.sample_valid(chorus_valid),
        .left_out(chorus_l),.right_out(chorus_r),.effect_blend(chorus_blend),.effect_busy(chorus_busy));
    piano_stereo_room #(.ENABLE(ROOM_ENABLE),.CONTROL_ENABLE(1)) u_room(
        .clk(clk),.rst_n(rst_n),.sample_valid_in(chorus_valid),
        .left_in(chorus_l),.right_in(chorus_r),.room_enable(room_enable),
        .sample_valid(sample_valid),.left_out(left_out),.right_out(right_out),
        .effect_blend(reverb_blend),.effect_busy(reverb_busy));
endmodule
