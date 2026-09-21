`include "../config/guitar_config.vh"

// Four fixed string voices: fret/event selection followed by one
// independent phase smoother per string.
module four_string_voice_control #(
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,
    parameter integer VIBRATO_TAP_COUNT = `VIBRATO_TAP_COUNT,
    parameter integer VIBRATO_MIN_INTERVAL = `VIBRATO_MIN_TAP_SAMPLES,
    parameter integer VIBRATO_MAX_INTERVAL = `VIBRATO_MAX_TAP_SAMPLES,
    parameter integer VIBRATO_EXIT_INTERVAL = `VIBRATO_EXIT_SAMPLES,
    parameter integer VIBRATO_WINDOW = `VIBRATO_WINDOW_SAMPLES,
    parameter [31:0] VIBRATO_LFO_PHASE_INC = `VIBRATO_LFO_PHASE_INC,
    parameter [15:0] VIBRATO_DEPTH_Q15 = `VIBRATO_DEPTH_Q15
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stable_valid,
    input  wire [15:0]  stable_fret_id,
    input  wire [3:0]   pluck_valid,
    input  wire         sample_ce,

    output wire [3:0]   note_on,
    output wire [3:0]   note_off,
    output wire [3:0]   slide_valid,
    output wire [3:0]   voice_active,
    output wire [15:0]  current_fret_id,
    output wire [127:0] target_phase_inc,
    output wire [127:0] phase_inc,
    output wire [3:0]   slide_busy,
    output wire [3:0]   vibrato_enable
);

    wire [31:0] target0;
    wire [31:0] target1;
    wire [31:0] target2;
    wire [31:0] target3;
    wire [127:0] phase_inc_base;

    fret_note_event #(
        .VIBRATO_TAP_COUNT(VIBRATO_TAP_COUNT),
        .VIBRATO_MIN_INTERVAL(VIBRATO_MIN_INTERVAL),
        .VIBRATO_MAX_INTERVAL(VIBRATO_MAX_INTERVAL),
        .VIBRATO_EXIT_INTERVAL(VIBRATO_EXIT_INTERVAL),
        .VIBRATO_WINDOW(VIBRATO_WINDOW)
    ) u_fret_note_event (
        .clk              (clk),
        .rst_n            (rst_n),
        .stable_valid     (stable_valid),
        .stable_fret_id   (stable_fret_id),
        .pluck_valid      (pluck_valid),
        .sample_ce        (sample_ce),
        .note_on          (note_on),
        .note_off         (note_off),
        .slide_valid      (slide_valid),
        .vibrato_enable   (vibrato_enable),
        .voice_active     (voice_active),
        .current_fret_id  (current_fret_id),
        .phase_inc        (target_phase_inc)
    );

    assign target0 = target_phase_inc[31:0];
    assign target1 = target_phase_inc[63:32];
    assign target2 = target_phase_inc[95:64];
    assign target3 = target_phase_inc[127:96];

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother0 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[0]),
        .voice_active    (voice_active[0]),
        .target_phase_inc(target0),
        .phase_inc       (phase_inc_base[31:0]),
        .busy            (slide_busy[0])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother1 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[1]),
        .voice_active    (voice_active[1]),
        .target_phase_inc(target1),
        .phase_inc       (phase_inc_base[63:32]),
        .busy            (slide_busy[1])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother2 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[2]),
        .voice_active    (voice_active[2]),
        .target_phase_inc(target2),
        .phase_inc       (phase_inc_base[95:64]),
        .busy            (slide_busy[2])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother3 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[3]),
        .voice_active    (voice_active[3]),
        .target_phase_inc(target3),
        .phase_inc       (phase_inc_base[127:96]),
        .busy            (slide_busy[3])
    );

    phase_vibrato_modulator #(.LFO_PHASE_INC(VIBRATO_LFO_PHASE_INC),
                              .DEPTH_Q15(VIBRATO_DEPTH_Q15)) u_vibrato0 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .enable(vibrato_enable[0]), .base_phase_inc(phase_inc_base[31:0]),
        .phase_inc(phase_inc[31:0])
    );
    phase_vibrato_modulator #(.LFO_PHASE_INC(VIBRATO_LFO_PHASE_INC),
                              .DEPTH_Q15(VIBRATO_DEPTH_Q15)) u_vibrato1 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .enable(vibrato_enable[1]), .base_phase_inc(phase_inc_base[63:32]),
        .phase_inc(phase_inc[63:32])
    );
    phase_vibrato_modulator #(.LFO_PHASE_INC(VIBRATO_LFO_PHASE_INC),
                              .DEPTH_Q15(VIBRATO_DEPTH_Q15)) u_vibrato2 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .enable(vibrato_enable[2]), .base_phase_inc(phase_inc_base[95:64]),
        .phase_inc(phase_inc[95:64])
    );
    phase_vibrato_modulator #(.LFO_PHASE_INC(VIBRATO_LFO_PHASE_INC),
                              .DEPTH_Q15(VIBRATO_DEPTH_Q15)) u_vibrato3 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .enable(vibrato_enable[3]), .base_phase_inc(phase_inc_base[127:96]),
        .phase_inc(phase_inc[127:96])
    );

endmodule
