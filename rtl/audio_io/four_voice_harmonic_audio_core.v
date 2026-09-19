`include "../config/guitar_config.vh"

// Four scheduled harmonic voices. This is intentionally separate from the
// legacy sine-only core so the production path remains selectable unchanged.
module four_voice_harmonic_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV,
    parameter integer HARMONICS  = `HARMONICS_MAX,
    parameter integer TIMBRE_BLEND_SAMPLES = `TIMBRE_BLEND_SAMPLES
) (
    input  wire          clk_audio_ref,
    input  wire          rst_n,
    input  wire [3:0]    note_on,
    input  wire [3:0]    note_off,
    input  wire [7:0]    velocity_level,
    input  wire [127:0]  phase_inc,
    input  wire          timbre_select,
    input  wire          sustain_enable,

    output wire          sample_tick,
    output wire          sample_valid,
    output wire signed [23:0] pcm_mix,
    output wire [3:0]    voice_active,
    output wire signed [95:0] voice_pcm,
    output wire [3:0]    voice_busy,
    output wire [3:0]    deadline_miss,
    output wire [8:0]    timbre_blend,
    output wire          timbre_busy
);

    wire sample_tick_i;
    wire sample_valid0;
    wire sample_valid1;
    wire sample_valid2;
    wire sample_valid3;
    wire signed [23:0] pcm0;
    wire signed [23:0] pcm1;
    wire signed [23:0] pcm2;
    wire signed [23:0] pcm3;
    wire active0;
    wire active1;
    wire active2;
    wire active3;
    wire busy0;
    wire busy1;
    wire busy2;
    wire busy3;
    wire deadline_miss0;
    wire deadline_miss1;
    wire deadline_miss2;
    wire deadline_miss3;

    reg [3:0] pending_note_on;
    reg [3:0] pending_note_off;
    wire [3:0] delivered_note_on;
    wire [3:0] delivered_note_off;

    assign delivered_note_on  = pending_note_on  | note_on;
    assign delivered_note_off = pending_note_off | note_off;
    assign sample_tick = sample_tick_i;
    assign voice_active = {active3, active2, active1, active0};
    assign voice_pcm = {pcm3, pcm2, pcm1, pcm0};
    assign voice_busy = {busy3, busy2, busy1, busy0};
    assign deadline_miss = {deadline_miss3, deadline_miss2,
                            deadline_miss1, deadline_miss0};

    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            pending_note_on  <= 4'd0;
            pending_note_off <= 4'd0;
        end
        else begin
            pending_note_on  <= pending_note_on  | note_on;
            pending_note_off <= pending_note_off | note_off;
            if (sample_tick_i) begin
                pending_note_on  <= 4'd0;
                pending_note_off <= 4'd0;
            end
        end
    end

    sample_tick_gen #(.DIVISOR(SAMPLE_DIV)) u_sample_tick_gen (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick_i)
    );

    timbre_blend_smoother #(
        .BLEND_SAMPLES(TIMBRE_BLEND_SAMPLES)
    ) u_timbre_blend_smoother (
        .clk           (clk_audio_ref),
        .rst_n         (rst_n),
        .sample_ce     (sample_tick_i),
        .timbre_select (timbre_select),
        .blend         (timbre_blend),
        .busy          (timbre_busy)
    );

    harmonic_voice_core #(.HARMONICS(HARMONICS)) u_voice0 (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_ce(sample_tick_i),
        .note_on(delivered_note_on[0]), .note_off(delivered_note_off[0]),
        .velocity_level(velocity_level[1:0]), .phase_inc(phase_inc[31:0]),
        .timbre_blend(timbre_blend),
        .sustain_enable(sustain_enable),
        .sample_valid(sample_valid0), .pcm_out(pcm0), .env_level(),
        .active(active0), .busy(busy0), .deadline_miss(deadline_miss0)
    );

    harmonic_voice_core #(.HARMONICS(HARMONICS)) u_voice1 (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_ce(sample_tick_i),
        .note_on(delivered_note_on[1]), .note_off(delivered_note_off[1]),
        .velocity_level(velocity_level[3:2]), .phase_inc(phase_inc[63:32]),
        .timbre_blend(timbre_blend),
        .sustain_enable(sustain_enable),
        .sample_valid(sample_valid1), .pcm_out(pcm1), .env_level(),
        .active(active1), .busy(busy1), .deadline_miss(deadline_miss1)
    );

    harmonic_voice_core #(.HARMONICS(HARMONICS)) u_voice2 (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_ce(sample_tick_i),
        .note_on(delivered_note_on[2]), .note_off(delivered_note_off[2]),
        .velocity_level(velocity_level[5:4]), .phase_inc(phase_inc[95:64]),
        .timbre_blend(timbre_blend),
        .sustain_enable(sustain_enable),
        .sample_valid(sample_valid2), .pcm_out(pcm2), .env_level(),
        .active(active2), .busy(busy2), .deadline_miss(deadline_miss2)
    );

    harmonic_voice_core #(.HARMONICS(HARMONICS)) u_voice3 (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_ce(sample_tick_i),
        .note_on(delivered_note_on[3]), .note_off(delivered_note_off[3]),
        .velocity_level(velocity_level[7:6]), .phase_inc(phase_inc[127:96]),
        .timbre_blend(timbre_blend),
        .sustain_enable(sustain_enable),
        .sample_valid(sample_valid3), .pcm_out(pcm3), .env_level(),
        .active(active3), .busy(busy3), .deadline_miss(deadline_miss3)
    );

    pcm24_mixer u_pcm24_mixer (
        .clk(clk_audio_ref), .rst_n(rst_n), .sample_valid_in(sample_valid0),
        .pcm0(pcm0), .pcm1(pcm1), .pcm2(pcm2), .pcm3(pcm3),
        .sample_valid(sample_valid), .pcm_out(pcm_mix)
    );

endmodule
