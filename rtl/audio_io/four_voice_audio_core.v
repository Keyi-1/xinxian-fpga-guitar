`include "../config/guitar_config.vh"

// Four independent voice cores followed by a saturated 24-bit mixer.
// Short event pulses are latched until the next audio sample tick.
module four_voice_audio_core #(
    parameter integer SAMPLE_DIV = `AUDIO_SAMPLE_DIV
) (
    input  wire          clk_audio_ref,
    input  wire          rst_n,
    input  wire [3:0]    note_on,
    input  wire [3:0]    note_off,
    input  wire [127:0]  phase_inc,

    output wire          sample_tick,
    output wire          sample_valid,
    output wire signed [23:0] pcm_mix,
    output wire [3:0]    voice_active,
    output wire signed [95:0] voice_pcm
);

    wire sample_tick0;
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

    reg [3:0] pending_note_on;
    reg [3:0] pending_note_off;

    wire [3:0] delivered_note_on;
    wire [3:0] delivered_note_off;

    assign delivered_note_on  = pending_note_on  | note_on;
    assign delivered_note_off = pending_note_off | note_off;

    assign sample_tick = sample_tick0;
    assign voice_active = {active3, active2, active1, active0};
    assign voice_pcm = {pcm3, pcm2, pcm1, pcm0};

    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            pending_note_on  <= 4'd0;
            pending_note_off <= 4'd0;
        end
        else begin
            pending_note_on  <= pending_note_on  | note_on;
            pending_note_off <= pending_note_off | note_off;

            if (sample_tick0) begin
                pending_note_on  <= 4'd0;
                pending_note_off <= 4'd0;
            end
        end
    end

    voice_audio_core #(.SAMPLE_DIV(SAMPLE_DIV)) u_voice0 (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (delivered_note_on[0]),
        .note_off     (delivered_note_off[0]),
        .phase_inc    (phase_inc[31:0]),
        .sample_tick  (sample_tick0),
        .sample_valid (sample_valid0),
        .pcm_out      (pcm0),
        .env_level    (),
        .active       (active0)
    );

    voice_audio_core #(.SAMPLE_DIV(SAMPLE_DIV)) u_voice1 (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (delivered_note_on[1]),
        .note_off     (delivered_note_off[1]),
        .phase_inc    (phase_inc[63:32]),
        .sample_tick  (),
        .sample_valid (sample_valid1),
        .pcm_out      (pcm1),
        .env_level    (),
        .active       (active1)
    );

    voice_audio_core #(.SAMPLE_DIV(SAMPLE_DIV)) u_voice2 (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (delivered_note_on[2]),
        .note_off     (delivered_note_off[2]),
        .phase_inc    (phase_inc[95:64]),
        .sample_tick  (),
        .sample_valid (sample_valid2),
        .pcm_out      (pcm2),
        .env_level    (),
        .active       (active2)
    );

    voice_audio_core #(.SAMPLE_DIV(SAMPLE_DIV)) u_voice3 (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (delivered_note_on[3]),
        .note_off     (delivered_note_off[3]),
        .phase_inc    (phase_inc[127:96]),
        .sample_tick  (),
        .sample_valid (sample_valid3),
        .pcm_out      (pcm3),
        .env_level    (),
        .active       (active3)
    );

    pcm24_mixer u_pcm24_mixer (
        .clk             (clk_audio_ref),
        .rst_n           (rst_n),
        .sample_valid_in (sample_valid0),
        .pcm0            (pcm0),
        .pcm1            (pcm1),
        .pcm2            (pcm2),
        .pcm3            (pcm3),
        .sample_valid    (sample_valid),
        .pcm_out         (pcm_mix)
    );

endmodule
