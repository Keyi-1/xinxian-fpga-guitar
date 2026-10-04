`include "guitar_config.vh"

// Dual-PCB validation: J13 selects pitch; MCP3208 CH0..3 pluck E/B/G/D.
// All runtime logic uses the board-verified 12.288 MHz audio clock.
module neo_full_chain_audio_test_top #(
    parameter integer MATRIX_CLK_DIV         = 768,
    parameter integer MATRIX_SETTLE_CYCLES   = 3,
    parameter integer MATRIX_DEBOUNCE_FRAMES = 5,
    parameter integer ADC_SPI_CLK_DIV        = `ADC_SPI_CLK_DIV,
    parameter [11:0] ADC_BASELINE_CODE        = 12'd2053,
    parameter [11:0] TRIGGER_THRESHOLD        = 12'd100,
    parameter [11:0] REARM_THRESHOLD          = 12'd30,
    parameter integer PLUCK_DEAD_SAMPLES     = 400,
    parameter integer PLUCK_SETTLE_SAMPLES   = 80,
    parameter integer AUDIO_SAMPLE_DIV       = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV         = `PT8211_REF_DIV,
    parameter integer SLIDE_SAMPLES          = `SLIDE_SAMPLES,
    parameter [1:0] FIXED_VELOCITY            = 2'd2,
    parameter integer LED_HOLD_CYCLES         = 1200000,
    parameter integer PLUCK_ATTACK_SAMPLES      = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES  = 9600,
    parameter integer PLUCK_FAST_SHIFT          = 13,
    parameter integer PLUCK_SLOW_SHIFT          = 16,
    parameter integer PLUCK_RELEASE_SHIFT       = 10,
    parameter integer PLUCK_IDLE_LEVEL          = 64
) (
    input wire audio_clk_12m288,
    input wire rst_n,
    inout wire ROW0, ROW1, ROW2, ROW3,
    input wire COL0, COL1, COL2, COL3, COL4, COL5, COL6, COL7,
    output wire adc_cs_n, adc_sclk, adc_mosi,
    input wire adc_miso,
    output wire dac_bclk, dac_lrck, dac_din,
    output wire pa_en_n,
    output wire [3:0] event_led
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

    // Preserve the physical-board-tested ADC path, including its odd-code
    // alignment compensation. Do not substitute the older FULL frontend.
    wire adc_sample_valid;
    wire [1:0] adc_sample_string;
    wire [11:0] adc_sample_data;
    wire [3:0] pluck_valid;

    mcp3208_four_channel_reader #(.CLK_DIV(ADC_SPI_CLK_DIV)) u_reader (
        .clk(audio_clk_12m288), .rst_n(audio_rst_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .sample_valid(adc_sample_valid),
        .sample_string(adc_sample_string), .sample_data(adc_sample_data)
    );
    four_string_pluck_detector #(
        .BASELINE_CODE(ADC_BASELINE_CODE),
        .TRIGGER_THRESHOLD(TRIGGER_THRESHOLD),
        .REARM_THRESHOLD(REARM_THRESHOLD),
        .DEAD_SAMPLES(PLUCK_DEAD_SAMPLES),
        .SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES)
    ) u_detector (
        .clk(audio_clk_12m288), .rst_n(audio_rst_n),
        .sample_valid(adc_sample_valid),
        .sample_string(adc_sample_string), .sample_data(adc_sample_data),
        .pluck_valid(pluck_valid)
    );

    wire sample_tick;
    wire [3:0] voice_active;
    wire [3:0] note_on, note_off;
    wire [127:0] target_phase_inc, smoothed_phase_inc, phase_inc;
    wire [3:0] slide_busy;

    neo_guitar_link_control u_link_control (
        .clk(audio_clk_12m288), .rst_n(audio_rst_n),
        .sample_tick(sample_tick), .stable_valid(stable_valid),
        .stable_fret_id(stable_fret_id), .pluck_valid(pluck_valid),
        .voice_active(voice_active), .smoothed_phase_inc(smoothed_phase_inc),
        .note_on(note_on), .note_off(note_off),
        .target_phase_inc(target_phase_inc)
    );

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : string_slide
        phase_slide_smoother #(.SLIDE_SAMPLES(SLIDE_SAMPLES)) u_smoother (
            .clk(audio_clk_12m288), .rst_n(audio_rst_n),
            .sample_ce(sample_tick), .note_on(note_on[g]),
            .voice_active(voice_active[g]),
            .target_phase_inc(target_phase_inc[g*32 +: 32]),
            .phase_inc(smoothed_phase_inc[g*32 +: 32]), .busy(slide_busy[g])
        );
        assign phase_inc[g*32 +: 32] = note_on[g] ?
            target_phase_inc[g*32 +: 32] : smoothed_phase_inc[g*32 +: 32];
    end endgenerate

    // Allocate only genuinely new voices. A still-active voice, including
    // its Release tail, retains its channel when the same string is replucked.
    // Launching on sample_tick also avoids uncounted pending voice starts.
    reg [3:0] voice_pan_right;
    reg pan_tie_right;
    reg [3:0] pan_plan;
    reg pan_tie_work;
    integer pan_left_count, pan_right_count, pan_index;
    always @* begin
        pan_plan = voice_pan_right;
        pan_tie_work = pan_tie_right;
        pan_left_count = 0;
        pan_right_count = 0;
        for (pan_index = 0; pan_index < 4; pan_index = pan_index + 1) begin
            if (voice_active[pan_index]) begin
                if (voice_pan_right[pan_index])
                    pan_right_count = pan_right_count + 1;
                else
                    pan_left_count = pan_left_count + 1;
            end
        end
        for (pan_index = 0; pan_index < 4; pan_index = pan_index + 1) begin
            if (note_on[pan_index] && !voice_active[pan_index]) begin
                if (pan_left_count < pan_right_count)
                    pan_plan[pan_index] = 1'b0;
                else if (pan_right_count < pan_left_count)
                    pan_plan[pan_index] = 1'b1;
                else begin
                    pan_plan[pan_index] = pan_tie_work;
                    pan_tie_work = ~pan_tie_work;
                end
                if (pan_plan[pan_index])
                    pan_right_count = pan_right_count + 1;
                else
                    pan_left_count = pan_left_count + 1;
            end
        end
    end

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            voice_pan_right <= 4'd0;
            pan_tie_right <= 1'b0;
        end
        else if (|note_on) begin
            voice_pan_right <= pan_plan;
            pan_tie_right <= pan_tie_work;
        end
    end

    // Same active-low 0.1 s per-string diagnostics as test3.
    reg [31:0] led_stretch [0:3];
    integer m;
    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            for (m = 0; m < 4; m = m + 1)
                led_stretch[m] <= 32'd0;
        end
        else begin
            for (m = 0; m < 4; m = m + 1) begin
                if (pluck_valid[m])
                    led_stretch[m] <= LED_HOLD_CYCLES;
                else if (led_stretch[m] != 0)
                    led_stretch[m] <= led_stretch[m] - 1'b1;
            end
        end
    end
    assign event_led = {led_stretch[3] == 0, led_stretch[2] == 0,
                        led_stretch[1] == 0, led_stretch[0] == 0};

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
        .velocity_level({4{FIXED_VELOCITY}}),
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

    // Preserve the verified post-reset amplifier policy to avoid per-note pops.
    assign pa_en_n = audio_rst_n ? 1'b0 : 1'b1;

endmodule


