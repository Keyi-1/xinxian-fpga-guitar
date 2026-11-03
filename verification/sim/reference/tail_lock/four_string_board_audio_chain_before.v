`include "../config/guitar_config.vh"

// Shared main audio path promoted from the listening-verified dual-PCB test.
// Legacy stereo effects are independent; piano uses a shared room.
// FFT receives the average of the final stereo channels.
module tail_before_four_string_board_audio_chain #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer REF_DIV = `PT8211_REF_DIV,
    parameter integer I2S_ENABLE = 0,
    parameter integer EXTERNAL_CONTROL_ENABLE = 0,
    parameter integer GAME_CUE_ENABLE = 0,
    parameter integer VIBRATO_ENABLE = 0,
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer CONTROL_PHASE_VALUE_BITS = `NOTE_PHASE_VALUE_BITS,
    parameter integer USE_HARMONIC = 0,
    parameter integer USE_PIANO = 0,
    parameter integer PIANO_HAMMER_ENABLE = 1,
    parameter integer PIANO_ROOM_ENABLE = 1,
    parameter integer PIANO_MODES = 8,
    parameter integer PIANO_CONTROL_ENABLE = 0,
    parameter integer PIANO_ROCK_ENABLE = 0,
    parameter integer ANTI_BEAT_ENABLE = `BOARD_ANTI_BEAT_ENABLE,
    parameter integer ANTI_BEAT_GAP_HZ = 80,
    parameter [8:0] ANTI_BEAT_PAIR_GAIN_Q8 = 9'd128,
    parameter integer PLUCK_ATTACK_SAMPLES = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES = 9600,
    parameter integer PLUCK_FAST_SHIFT = 13,
    parameter integer PLUCK_SLOW_SHIFT = 16,
    parameter integer PLUCK_RELEASE_SHIFT = 10,
    parameter integer PLUCK_IDLE_LEVEL = 64
) (
    input wire clk_audio_ref, rst_n, stable_valid,
    input wire [15:0] stable_fret_id,
    input wire [3:0] pluck_valid,
    input wire [7:0] velocity_level,
    input wire timbre_select, rock_select, chorus_enable, sustain_enable,
    input wire harmony_enable, reverb_enable,
    output wire sample_tick, pcm_mix_valid,
    output wire signed [23:0] pcm_mix,
    output wire [3:0] voice_active,
    output wire [95:0] voice_pcm,
    output wire dac_bclk, dac_lrck, dac_din,
    // Passive display taps; synthesis removes them in audio-only builds.
    output wire [127:0] display_phase_inc,
    output wire [3:0] display_note_on,
    output wire display_voice_sample_valid,
    output wire i2s_bclk, i2s_ws, i2s_data,
    input wire [3:0] external_note_on,external_note_off,external_force_release,
    input wire [127:0] external_phase_inc,
    input wire [3:0] external_vibrato_enable,
    input wire game_cue_enable,game_miss_event,
    output wire control_pipeline_idle,control_timbre_busy
);
    wire [3:0] note_on, note_off, slide_busy;
    wire [127:0] target_phase_inc, smoothed_phase_inc, phase_inc, unmodulated_phase_inc;
    wire voice_sample_valid;
    assign display_phase_inc=phase_inc;
    assign display_note_on=note_on;
    assign display_voice_sample_valid=voice_sample_valid;
    wire signed [23:0] unused_saturated_mix;
    wire [3:0] deadline_miss;
    wire [8:0] timbre_blend, chorus_blend, reverb_blend;
    wire [8:0] rock_blend;
    wire timbre_busy, chorus_busy, reverb_busy;
    assign control_timbre_busy=timbre_busy;
    wire [7:0] piano_profile;

    generate if(EXTERNAL_CONTROL_ENABLE==0)begin : performance_control
    guitar_play_control u_play_control (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_tick(sample_tick),
        .stable_valid(stable_valid), .stable_fret_id(stable_fret_id),
        .pluck_valid(pluck_valid), .voice_active(voice_active),
        .smoothed_phase_inc(smoothed_phase_inc),
        .note_on(note_on), .note_off(note_off), .target_phase_inc(target_phase_inc)
    );
    end else begin : event_control
        assign note_on=external_note_on;
        assign note_off=external_note_off;
        assign target_phase_inc=external_phase_inc;
    end endgenerate
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : string_slide
        phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES),
            .PHASE_VALUE_BITS(CONTROL_PHASE_VALUE_BITS)) u_smoother (
            .clk(clk_audio_ref), .rst_n(rst_n), .sample_ce(sample_tick),
            .note_on(note_on[g]), .voice_active(voice_active[g]),
            .target_phase_inc(target_phase_inc[g*32 +: 32]),
            .phase_inc(smoothed_phase_inc[g*32 +: 32]), .busy(slide_busy[g])
        );
        assign unmodulated_phase_inc[g*32 +: 32] = note_on[g] ?
            target_phase_inc[g*32 +: 32] : smoothed_phase_inc[g*32 +: 32];
    end endgenerate

    generate if(VIBRATO_ENABLE!=0)begin:performance_vibrato
        wire [3:0] enabled=external_vibrato_enable & voice_active & ~slide_busy & ~note_on &
            (EXTERNAL_CONTROL_ENABLE!=0 ? ~external_force_release : 4'hf);
        wire busy,deadline_miss;
        four_string_vibrato_serial modulator(.clk(clk_audio_ref),.rst_n(rst_n),
            .sample_tick(sample_tick),.enable(enabled),.base_phase_inc(unmodulated_phase_inc),
            .phase_inc(phase_inc),.busy(busy),.deadline_miss(deadline_miss));
    end else begin:no_vibrato
        assign phase_inc=unmodulated_phase_inc;
    end endgenerate

    generate if (USE_PIANO != 0) begin : g_piano
        four_voice_piano_audio_core #(.SAMPLE_DIV(SAMPLE_DIV),
            .HAMMER_ENABLE(PIANO_HAMMER_ENABLE),.MODES(PIANO_MODES),
            .CONTROL_ENABLE(PIANO_CONTROL_ENABLE),.ROCK_ENABLE(PIANO_ROCK_ENABLE),
            .FORCE_RELEASE_ENABLE(EXTERNAL_CONTROL_ENABLE)) u_core (
            .clk_audio_ref(clk_audio_ref),.rst_n(rst_n),.note_on(note_on),.note_off(note_off),
            .velocity_level(velocity_level),.phase_inc(phase_inc),.sample_tick(sample_tick),
            .timbre_select(timbre_select),.rock_select(rock_select),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),
            .force_release(external_force_release),
            .sample_valid(voice_sample_valid),.voice_active(voice_active),.voice_pcm(voice_pcm),
            .voice_profile(piano_profile),.deadline_miss(deadline_miss),
            .timbre_blend(timbre_blend),.rock_blend(rock_blend),.timbre_busy(timbre_busy));
    end else if (USE_HARMONIC == 0) begin : g_sine
        four_voice_audio_core #(.SAMPLE_DIV(SAMPLE_DIV), .PLUCK_MODE(1), .PLUCK_ATTACK_SAMPLES(PLUCK_ATTACK_SAMPLES),
                .PLUCK_FAST_DECAY_SAMPLES(PLUCK_FAST_DECAY_SAMPLES),
                .PLUCK_FAST_SHIFT(PLUCK_FAST_SHIFT), .PLUCK_SLOW_SHIFT(PLUCK_SLOW_SHIFT),
                .PLUCK_RELEASE_SHIFT(PLUCK_RELEASE_SHIFT), .PLUCK_IDLE_LEVEL(PLUCK_IDLE_LEVEL)
        ) u_core (
            .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
            .note_on(note_on), .note_off(note_off), .velocity_level(velocity_level),
            .phase_inc(phase_inc), .sample_tick(sample_tick),
            .sample_valid(voice_sample_valid), .pcm_mix(unused_saturated_mix),
            .voice_active(voice_active), .voice_pcm(voice_pcm)
        );
        assign deadline_miss = 4'd0;
        assign timbre_blend = 9'd0;
        assign rock_blend = 9'd0;
        assign timbre_busy = 1'b0;
    end else begin : g_harmonic
        assign rock_blend = 9'd0;
        four_voice_harmonic_audio_core #(.SAMPLE_DIV(SAMPLE_DIV), .PLUCK_MODE(1), .PLUCK_ATTACK_SAMPLES(PLUCK_ATTACK_SAMPLES),
                .PLUCK_FAST_DECAY_SAMPLES(PLUCK_FAST_DECAY_SAMPLES),
                .PLUCK_FAST_SHIFT(PLUCK_FAST_SHIFT), .PLUCK_SLOW_SHIFT(PLUCK_SLOW_SHIFT),
                .PLUCK_RELEASE_SHIFT(PLUCK_RELEASE_SHIFT), .PLUCK_IDLE_LEVEL(PLUCK_IDLE_LEVEL)
        ) u_core (
            .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
            .note_on(note_on), .note_off(note_off), .velocity_level(velocity_level),
            .phase_inc(phase_inc), .timbre_select(timbre_select),
            .sustain_enable(sustain_enable), .sample_tick(sample_tick),
            .sample_valid(voice_sample_valid), .pcm_mix(unused_saturated_mix),
            .voice_active(voice_active), .voice_pcm(voice_pcm),
            .voice_busy(), .deadline_miss(deadline_miss),
            .timbre_blend(timbre_blend), .timbre_busy(timbre_busy)
        );
    end endgenerate

    wire [3:0] voice_pan_right;
    wire [35:0] voice_gain_q8;
    four_voice_antibeat_allocator #(
        .ENABLE(ANTI_BEAT_ENABLE), .NEAR_GAP_HZ(ANTI_BEAT_GAP_HZ),
        .PAIR_GAIN_Q8(ANTI_BEAT_PAIR_GAIN_Q8)
    ) u_allocator (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_tick(sample_tick),
        .note_on(note_on), .voice_active(voice_active),
        .selected_phase_inc(target_phase_inc), .audible_phase_inc(phase_inc),
        .pan_right(voice_pan_right), .gain_q8(voice_gain_q8)
    );

    wire signed [23:0] voice_pcm0 = voice_pcm[23:0];
    wire signed [23:0] voice_pcm1 = voice_pcm[47:24];
    wire signed [23:0] voice_pcm2 = voice_pcm[71:48];
    wire signed [23:0] voice_pcm3 = voice_pcm[95:72];

    reg signed [27:0] mix_left_primary;
    reg signed [27:0] mix_right_primary;
    reg signed [23:0] pcm_left_scaled;
    reg signed [23:0] pcm_right_scaled;

    generate if (USE_PIANO != 0) begin : piano_stereo
        reg signed [27:0] lsum,rsum;
        reg signed [27:0] value, half, eighth, sixteenth;
        integer p;
        always @* begin
            lsum=0;rsum=0;value=0;half=0;eighth=0;sixteenth=0;
            for(p=0;p<4;p=p+1) begin
                value=$signed({{4{voice_pcm[p*24+23]}},voice_pcm[p*24+:24]});
                half=value>>>1;eighth=value>>>3;sixteenth=value>>>4;
                // Fixed string positions avoid a gain/pan jump when a live
                // voice is re-struck with another pitch/timbre profile.
                case(p)
                    0: begin lsum=lsum+half+eighth;rsum=rsum+half+(value>>>2);end
                    1: begin lsum=lsum+half+eighth+(value>>>5);rsum=rsum+half+eighth+sixteenth+(value>>>5);end
                    2: begin lsum=lsum+half+eighth+sixteenth+(value>>>5);rsum=rsum+half+eighth+(value>>>5);end
                    default: begin lsum=lsum+half+(value>>>2);rsum=rsum+half+eighth;end
                endcase
            end
            // Static /2 headroom, every note audible in both channels. The ROM
            // amplitude bounds include the hammer and all four aligned voices.
            pcm_left_scaled=lsum[24:1];pcm_right_scaled=rsum[24:1];
            mix_left_primary=lsum;mix_right_primary=rsum;
        end
    end else if (ANTI_BEAT_ENABLE == 0) begin : legacy_stereo
    always @* begin
        mix_left_primary  = 28'sd0;
        mix_right_primary = 28'sd0;

        if (voice_pan_right[0])
            mix_right_primary = mix_right_primary +
                $signed({{4{voice_pcm0[23]}}, voice_pcm0});
        else
            mix_left_primary = mix_left_primary +
                $signed({{4{voice_pcm0[23]}}, voice_pcm0});
        if (voice_pan_right[1])
            mix_right_primary = mix_right_primary +
                $signed({{4{voice_pcm1[23]}}, voice_pcm1});
        else
            mix_left_primary = mix_left_primary +
                $signed({{4{voice_pcm1[23]}}, voice_pcm1});
        if (voice_pan_right[2])
            mix_right_primary = mix_right_primary +
                $signed({{4{voice_pcm2[23]}}, voice_pcm2});
        else
            mix_left_primary = mix_left_primary +
                $signed({{4{voice_pcm2[23]}}, voice_pcm2});
        if (voice_pan_right[3])
            mix_right_primary = mix_right_primary +
                $signed({{4{voice_pcm3[23]}}, voice_pcm3});
        else
            mix_left_primary = mix_left_primary +
                $signed({{4{voice_pcm3[23]}}, voice_pcm3});

        // Keep the primary channels fully separated.  Dynamic allocation
        // guarantees at most two active voices per side, so dividing each
        // primary sum by two reproduces the previously successful hard-stereo
        // pair behaviour for any first two voices without crossfeed beating.
        pcm_left_scaled  = mix_left_primary[24:1];
        pcm_right_scaled = mix_right_primary[24:1];
    end
    end else begin : antibeat_stereo
        wire signed [33:0] weighted [0:3];
        genvar m;
        for (m = 0; m < 4; m = m + 1) begin : weight
            assign weighted[m] = $signed(voice_pcm[m*24 +: 24]) *
                                 $signed({1'b0,voice_gain_q8[m*9 +: 9]});
        end
        reg signed [35:0] left_sum, right_sum;
        reg signed [26:0] left_scaled, right_scaled;
        integer x;
        always @* begin
            left_sum = 0; right_sum = 0;
            for (x = 0; x < 4; x = x + 1) begin
                if (voice_pan_right[x])
                    right_sum = right_sum + $signed({{2{weighted[x][33]}},weighted[x]});
                else
                    left_sum = left_sum + $signed({{2{weighted[x][33]}},weighted[x]});
            end
            // Q8 gain and the existing per-channel /2 headroom.
            left_scaled = left_sum[35:9]; right_scaled = right_sum[35:9];
            if (left_scaled > 27'sd8388607) pcm_left_scaled = 24'sh7fffff;
            else if (left_scaled < -27'sd8388608) pcm_left_scaled = 24'sh800000;
            else pcm_left_scaled = left_scaled[23:0];
            if (right_scaled > 27'sd8388607) pcm_right_scaled = 24'sh7fffff;
            else if (right_scaled < -27'sd8388608) pcm_right_scaled = 24'sh800000;
            else pcm_right_scaled = right_scaled[23:0];
            mix_left_primary = 0; mix_right_primary = 0;
        end
    end endgenerate

    reg [1:0] rock_drive_level;
    integer v;
    always @* begin
        rock_drive_level = 0;
        for (v = 0; v < 4; v = v + 1)
            if (voice_active[v] && velocity_level[v*2 +: 2] > rock_drive_level)
                rock_drive_level = velocity_level[v*2 +: 2];
    end
    wire stereo_valid;
    wire signed [23:0] pcm_left_music, pcm_right_music;
    wire signed [23:0] pcm_left_final, pcm_right_final;
    generate if(USE_PIANO!=0 && PIANO_CONTROL_ENABLE!=0)begin : piano_effects
        piano_stereo_effects #(.ROOM_ENABLE(PIANO_ROOM_ENABLE)) u_effects (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_valid_in(voice_sample_valid),
            .left_in(pcm_left_scaled),.right_in(pcm_right_scaled),
            .drive_level(rock_drive_level),.timbre_blend(timbre_blend),
            .chorus_enable(chorus_enable),.room_enable(reverb_enable),
            .sample_valid(stereo_valid),.left_out(pcm_left_music),.right_out(pcm_right_music),
            .chorus_blend(chorus_blend),.reverb_blend(reverb_blend),
            .chorus_busy(chorus_busy),.reverb_busy(reverb_busy));
    end else if(USE_PIANO!=0) begin : piano_room
        piano_stereo_room #(.ENABLE(PIANO_ROOM_ENABLE)) u_room (
            .clk(clk_audio_ref),.rst_n(rst_n),.sample_valid_in(voice_sample_valid),
            .left_in(pcm_left_scaled),.right_in(pcm_right_scaled),
            .room_enable(1'b0),.effect_blend(),.effect_busy(),
            .sample_valid(stereo_valid),.left_out(pcm_left_music),.right_out(pcm_right_music));
        assign chorus_blend=0;assign chorus_busy=0;assign reverb_blend=0;assign reverb_busy=0;
    end else begin : legacy_effects
    stereo_audio_effects #(.ENABLE(USE_HARMONIC)) u_effects (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_valid_in(voice_sample_valid),
        .pcm_left(pcm_left_scaled), .pcm_right(pcm_right_scaled),
        .drive_level(rock_drive_level), .timbre_blend(timbre_blend),
        .chorus_enable(chorus_enable), .reverb_enable(reverb_enable),
        .sample_valid(stereo_valid), .left_out(pcm_left_music), .right_out(pcm_right_music),
        .chorus_blend(chorus_blend), .chorus_busy(chorus_busy),
        .reverb_blend(reverb_blend), .reverb_busy(reverb_busy)
    );
    end endgenerate
    generate if(GAME_CUE_ENABLE!=0)begin : game_feedback
        game_miss_audio_cue u_cue(.clk(clk_audio_ref),.rst_n(rst_n),.sample_valid(stereo_valid),
            .enabled(game_cue_enable),.trigger(game_miss_event),
            .left_in(pcm_left_music),.right_in(pcm_right_music),
            .left_out(pcm_left_final),.right_out(pcm_right_final));
    end else begin : no_game_feedback
        assign pcm_left_final=pcm_left_music;
        assign pcm_right_final=pcm_right_music;
    end endgenerate
    wire signed [24:0] spectrum_sum =
        $signed({pcm_left_final[23],pcm_left_final}) +
        $signed({pcm_right_final[23],pcm_right_final});
    assign pcm_mix = spectrum_sum[24:1];
    assign pcm_mix_valid = stereo_valid;

    wire pcm16_left_valid, pcm16_right_valid;
    assign control_pipeline_idle=!(voice_sample_valid || stereo_valid || pcm16_left_valid || pcm16_right_valid);
    wire signed [15:0] pcm16_left_out, pcm16_right_out;
    pcm24_to_16 u_pcm_left (
        .clk(clk_audio_ref), .rst_n(rst_n), .pcm_valid(stereo_valid),
        .pcm_in(pcm_left_final), .sample_valid(pcm16_left_valid), .sample_out(pcm16_left_out)
    );
    pcm24_to_16 u_pcm_right (
        .clk(clk_audio_ref), .rst_n(rst_n), .pcm_valid(stereo_valid),
        .pcm_in(pcm_right_final), .sample_valid(pcm16_right_valid), .sample_out(pcm16_right_out)
    );
    pt8211_tx #(.REF_DIV(REF_DIV)) u_pt8211_tx (
        .clk_audio_ref(clk_audio_ref), .rst_n(rst_n), .sample_valid(pcm16_left_valid),
        .sample_left(pcm16_left_out), .sample_right(pcm16_right_out),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din)
    );
    generate if (I2S_ENABLE != 0) begin : standard_i2s
        // REF_DIV is even for the board's 12.288 MHz / 48 kHz clocks.
        // Same quantized, post-effect pair; no second synthesis/effects path.
        i2s_tx #(.REF_DIV(REF_DIV/2)) u_tx (
            .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
            .sample_valid(pcm16_left_valid),
            .sample_left(pcm16_left_out), .sample_right(pcm16_right_out),
            .i2s_bclk(i2s_bclk), .i2s_ws(i2s_ws), .i2s_data(i2s_data)
        );
    end else begin : no_i2s
        assign i2s_bclk=1'b0;
        assign i2s_ws=1'b0;
        assign i2s_data=1'b0;
    end endgenerate
endmodule
