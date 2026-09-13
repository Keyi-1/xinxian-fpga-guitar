`include "../config/guitar_config.vh"

// Four fixed string voices: fret/event selection followed by one
// independent phase smoother per string.
module four_string_voice_control #(
    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES
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
    output wire [3:0]   slide_busy
);

    wire [31:0] target0;
    wire [31:0] target1;
    wire [31:0] target2;
    wire [31:0] target3;

    fret_note_event u_fret_note_event (
        .clk              (clk),
        .rst_n            (rst_n),
        .stable_valid     (stable_valid),
        .stable_fret_id   (stable_fret_id),
        .pluck_valid      (pluck_valid),
        .note_on          (note_on),
        .note_off         (note_off),
        .slide_valid      (slide_valid),
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
        .phase_inc       (phase_inc[31:0]),
        .busy            (slide_busy[0])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother1 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[1]),
        .voice_active    (voice_active[1]),
        .target_phase_inc(target1),
        .phase_inc       (phase_inc[63:32]),
        .busy            (slide_busy[1])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother2 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[2]),
        .voice_active    (voice_active[2]),
        .target_phase_inc(target2),
        .phase_inc       (phase_inc[95:64]),
        .busy            (slide_busy[2])
    );

    phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother3 (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce       (sample_ce),
        .note_on         (note_on[3]),
        .voice_active    (voice_active[3]),
        .target_phase_inc(target3),
        .phase_inc       (phase_inc[127:96]),
        .busy            (slide_busy[3])
    );

endmodule
