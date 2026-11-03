`include "../config/guitar_config.vh"

// NEO Dock 31005 board test for the 4x8 fret matrix and four simultaneous
// audio voices.  The matrix scan is used only to update stable note state;
// it never gates an oscillator, envelope, PCM sample, or PT8211 time slot.
module neo_four_string_matrix_audio_test_top #(
    // 12.288 MHz defaults:
    //   768 clocks x (3 settle steps + 1 capture step) = 250 us/row
    //   four rows = 1 ms/frame, followed by five-frame debounce.
    parameter integer MATRIX_CLK_DIV         = 768,
    parameter integer MATRIX_SETTLE_CYCLES   = 3,
    parameter integer MATRIX_DEBOUNCE_FRAMES = 5,
    parameter integer AUDIO_SAMPLE_DIV       = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV         = `PT8211_REF_DIV,
    // Contacts that settle inside this 30 ms window launch on one audio tick.
    parameter integer CHORD_CAPTURE_SAMPLES     = 1440,
    // Multiplier-free, two-stage natural-decay envelope parameters.
    parameter integer PLUCK_ATTACK_SAMPLES      = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES  = 9600,
    parameter integer PLUCK_FAST_SHIFT          = 13,
    parameter integer PLUCK_SLOW_SHIFT          = 16,
    parameter integer PLUCK_RELEASE_SHIFT       = 10,
    parameter integer PLUCK_IDLE_LEVEL          = 64
) (
    input  wire audio_clk_12m288,
    input  wire rst_n,

    inout  wire ROW0,
    inout  wire ROW1,
    inout  wire ROW2,
    inout  wire ROW3,

    input  wire COL0,
    input  wire COL1,
    input  wire COL2,
    input  wire COL3,
    input  wire COL4,
    input  wire COL5,
    input  wire COL6,
    input  wire COL7,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n
);

    // KEY0 assertion is asynchronous.  Its release is synchronized into the
    // 12.288 MHz domain, matching the already verified MINIMAL board wrapper.
    reg [1:0] audio_rst_sync;
    wire      audio_rst_n;

    always @(posedge audio_clk_12m288 or negedge rst_n) begin
        if (!rst_n)
            audio_rst_sync <= 2'b00;
        else
            audio_rst_sync <= {audio_rst_sync[0], 1'b1};
    end

    assign audio_rst_n = audio_rst_sync[1];

    // Synchronize the eight asynchronous contact inputs before scanning.
    wire [7:0] col_pins_n;
    reg  [7:0] col_meta_n;
    reg  [7:0] col_sync_n;

    assign col_pins_n = {COL7, COL6, COL5, COL4,
                         COL3, COL2, COL1, COL0};

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            col_meta_n <= 8'hff;
            col_sync_n <= 8'hff;
        end
        else begin
            col_meta_n <= col_pins_n;
            col_sync_n <= col_meta_n;
        end
    end

    wire [3:0]  row_oe;
    wire [3:0]  row_drive_n;
    wire         stable_valid;
    wire [31:0]  stable_fret_mask;
    wire [15:0]  stable_fret_id;

    matrix_scanner #(
        .CLK_DIV        (MATRIX_CLK_DIV),
        .SETTLE_CYCLES  (MATRIX_SETTLE_CYCLES),
        .DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES)
    ) u_matrix_scanner (
        .clk             (audio_clk_12m288),
        .rst_n           (audio_rst_n),
        .col_in_n        (col_sync_n),
        .row_oe          (row_oe),
        .row_drive_n     (row_drive_n),
        .frame_valid     (),
        .fret_mask       (),
        .fret_id         (),
        .stable_valid    (stable_valid),
        .stable_fret_mask(stable_fret_mask),
        .stable_fret_id  (stable_fret_id)
    );

    // Only the selected row is driven low.  Every unselected row is high-Z;
    // it is never driven high against another pressed contact.
    assign ROW0 = row_oe[0] ? row_drive_n[0] : 1'bz;
    assign ROW1 = row_oe[1] ? row_drive_n[1] : 1'bz;
    assign ROW2 = row_oe[2] ? row_drive_n[2] : 1'bz;
    assign ROW3 = row_oe[3] ? row_drive_n[3] : 1'bz;

    // A zero fret ID also represents "no contact", so presence is taken from
    // the corresponding stable mask byte.  Each string owns an independent
    // note-on/note-off state; scan-row changes cannot create new events.
    wire [3:0] pressed_stable;
    reg  [3:0] pressed_previous;
    reg  [3:0] note_on;
    reg  [3:0] note_off;
    reg  [3:0] pending_press;
    reg        capture_active;
    reg [31:0] capture_age;
    reg  [3:0] voice_pan_right;
    reg        pan_tie_right;

    wire sample_tick;
    wire [3:0] voice_active;

    assign pressed_stable = {
        |stable_fret_mask[31:24],
        |stable_fret_mask[23:16],
        |stable_fret_mask[15:8],
        |stable_fret_mask[7:0]
    };

    wire [3:0] press_edge_now;
    wire [3:0] release_edge_now;
    wire [3:0] capture_mask_now;

    assign press_edge_now = stable_valid ?
                            (pressed_stable & ~pressed_previous) : 4'b0000;
    assign release_edge_now = stable_valid ?
                              (~pressed_stable & pressed_previous) : 4'b0000;
    assign capture_mask_now =
        (pending_press | press_edge_now) & ~release_edge_now;

    // Plan a stable primary channel for each newly launched voice.  Existing
    // voices never move in mid-note.  A batch is assigned to the less loaded
    // side, alternating ties, so any first two voices occupy opposite sides.
    reg [3:0] pan_plan;
    reg       pan_tie_after_plan;
    reg       pan_tie_work;
    integer   pan_left_count;
    integer   pan_right_count;
    integer   pan_index;

    always @* begin
        pan_plan        = voice_pan_right;
        pan_tie_work    = pan_tie_right;
        pan_left_count  = 0;
        pan_right_count = 0;

        for (pan_index = 0; pan_index < 4; pan_index = pan_index + 1) begin
            if (voice_active[pan_index] && !capture_mask_now[pan_index]) begin
                if (voice_pan_right[pan_index])
                    pan_right_count = pan_right_count + 1;
                else
                    pan_left_count = pan_left_count + 1;
            end
        end

        for (pan_index = 0; pan_index < 4; pan_index = pan_index + 1) begin
            if (capture_mask_now[pan_index]) begin
                if (pan_left_count < pan_right_count) begin
                    pan_plan[pan_index] = 1'b0;
                    pan_left_count = pan_left_count + 1;
                end
                else if (pan_right_count < pan_left_count) begin
                    pan_plan[pan_index] = 1'b1;
                    pan_right_count = pan_right_count + 1;
                end
                else begin
                    pan_plan[pan_index] = pan_tie_work;
                    pan_tie_work = ~pan_tie_work;
                    if (pan_plan[pan_index])
                        pan_right_count = pan_right_count + 1;
                    else
                        pan_left_count = pan_left_count + 1;
                end
            end
        end

        pan_tie_after_plan = pan_tie_work;
    end

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            pressed_previous <= 4'b0000;
            note_on          <= 4'b0000;
            note_off         <= 4'b0000;
            pending_press    <= 4'b0000;
            capture_active   <= 1'b0;
            capture_age      <= 32'd0;
            voice_pan_right  <= 4'b0000;
            pan_tie_right    <= 1'b0;
        end
        else begin
            note_on  <= 4'b0000;
            note_off <= 4'b0000;

            if (stable_valid) begin
                pressed_previous <= pressed_stable;

                // Releasing a fret damps only that string.  A contact that is
                // released during capture is removed before it can launch.
                if (|release_edge_now) begin
                    note_off     <= release_edge_now & voice_active;
                    pending_press <= capture_mask_now;
                end

                if (|press_edge_now) begin
                    if (!capture_active) begin
                        capture_active <= 1'b1;
                        capture_age    <= 32'd0;
                        pending_press  <= press_edge_now;
                    end
                    else begin
                        pending_press <= capture_mask_now;
                    end
                end
            end

            // Capture time is measured at the audio sample rate.  Every edge
            // collected in the window is launched as one sample-aligned chord.
            if (sample_tick && capture_active) begin
                if (capture_age >= CHORD_CAPTURE_SAMPLES - 1) begin
                    if (|capture_mask_now) begin
                        note_on         <= capture_mask_now;
                        voice_pan_right <= pan_plan;
                        pan_tie_right   <= pan_tie_after_plan;
                    end
                    pending_press  <= 4'b0000;
                    capture_active <= 1'b0;
                    capture_age    <= 32'd0;
                end
                else begin
                    capture_age <= capture_age + 1'b1;
                end
            end
        end
    end

    // ROM layout is nine notes per string:
    //   string 0: E4 + fret 0..8
    //   string 1: B3 + fret 0..8
    //   string 2: G3 + fret 0..8
    //   string 3: D3 + fret 0..8
    wire [5:0] phase_addr0 = {2'b00, stable_fret_id[3:0]};
    wire [5:0] phase_addr1 = 6'd9  + stable_fret_id[7:4];
    wire [5:0] phase_addr2 = 6'd18 + stable_fret_id[11:8];
    wire [5:0] phase_addr3 = 6'd27 + stable_fret_id[15:12];

    wire [31:0] phase_inc0;
    wire [31:0] phase_inc1;
    wire [31:0] phase_inc2;
    wire [31:0] phase_inc3;
    wire [127:0] phase_inc;

    note_phase_table u_phase_table0 (
        .addr(phase_addr0), .phase_inc(phase_inc0)
    );
    note_phase_table u_phase_table1 (
        .addr(phase_addr1), .phase_inc(phase_inc1)
    );
    note_phase_table u_phase_table2 (
        .addr(phase_addr2), .phase_inc(phase_inc2)
    );
    note_phase_table u_phase_table3 (
        .addr(phase_addr3), .phase_inc(phase_inc3)
    );

    assign phase_inc = {phase_inc3, phase_inc2, phase_inc1, phase_inc0};

    wire                 voice_sample_valid;
    wire signed [23:0]    unused_saturated_mix;
    wire signed [95:0]   voice_pcm;

    four_voice_audio_core #(
        .SAMPLE_DIV              (AUDIO_SAMPLE_DIV),
        .PLUCK_MODE              (1),
        .PLUCK_ATTACK_SAMPLES    (PLUCK_ATTACK_SAMPLES),
        .PLUCK_FAST_DECAY_SAMPLES(PLUCK_FAST_DECAY_SAMPLES),
        .PLUCK_FAST_SHIFT        (PLUCK_FAST_SHIFT),
        .PLUCK_SLOW_SHIFT        (PLUCK_SLOW_SHIFT),
        .PLUCK_RELEASE_SHIFT     (PLUCK_RELEASE_SHIFT),
        .PLUCK_IDLE_LEVEL        (PLUCK_IDLE_LEVEL)
    ) u_four_voice_audio_core (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (audio_rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        // Fixed level 2 gives a stronger pluck-like Attack/Decay profile.
        // The stereo pair mixers below still guarantee numeric headroom.
        .velocity_level(8'b10_10_10_10),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (voice_sample_valid),
        .pcm_mix      (unused_saturated_mix),
        .voice_active (voice_active),
        .voice_pcm    (voice_pcm)
    );

    wire signed [23:0] voice_pcm0 = voice_pcm[23:0];
    wire signed [23:0] voice_pcm1 = voice_pcm[47:24];
    wire signed [23:0] voice_pcm2 = voice_pcm[71:48];
    wire signed [23:0] voice_pcm3 = voice_pcm[95:72];

    reg signed [27:0] mix_left_primary;
    reg signed [27:0] mix_right_primary;
    reg signed [23:0] pcm_left_scaled;
    reg signed [23:0] pcm_right_scaled;

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

    wire               pcm16_left_valid;
    wire               pcm16_right_valid;
    wire signed [15:0] pcm16_left_out;
    wire signed [15:0] pcm16_right_out;

    pcm24_to_16 u_pcm24_to_16_left (
        .clk         (audio_clk_12m288),
        .rst_n       (audio_rst_n),
        .pcm_valid   (voice_sample_valid),
        .pcm_in      (pcm_left_scaled),
        .sample_valid(pcm16_left_valid),
        .sample_out  (pcm16_left_out)
    );

    pcm24_to_16 u_pcm24_to_16_right (
        .clk         (audio_clk_12m288),
        .rst_n       (audio_rst_n),
        .pcm_valid   (voice_sample_valid),
        .pcm_in      (pcm_right_scaled),
        .sample_valid(pcm16_right_valid),
        .sample_out  (pcm16_right_out)
    );

    pt8211_tx #(
        .REF_DIV(PT8211_REF_DIV)
    ) u_pt8211_tx (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (audio_rst_n),
        // Both converters share one clock and one valid input, so their valid
        // pulses are cycle-aligned.  The left pulse clocks the stereo frame.
        .sample_valid (pcm16_left_valid),
        .sample_left  (pcm16_left_out),
        .sample_right (pcm16_right_out),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    // NEO Dock amplifier shutdown is active high at this wrapper boundary.
    // Keep it muted during reset and while every envelope is idle.
    // Do not power-cycle the analogue amplifier at every note boundary.  The
    // startup transient was audible as a strong pop.  Reset still mutes it.
    assign pa_en_n = audio_rst_n ? 1'b0 : 1'b1;

endmodule
