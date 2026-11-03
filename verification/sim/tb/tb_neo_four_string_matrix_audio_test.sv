`timescale 1ns/1ps

module tb_neo_four_string_matrix_audio_test;

    reg audio_clk_12m288;
    reg rst_n;
    reg [31:0] pressed;

    tri ROW0;
    tri ROW1;
    tri ROW2;
    tri ROW3;

    wire [7:0] selected_columns_n;
    wire COL0 = selected_columns_n[0];
    wire COL1 = selected_columns_n[1];
    wire COL2 = selected_columns_n[2];
    wire COL3 = selected_columns_n[3];
    wire COL4 = selected_columns_n[4];
    wire COL5 = selected_columns_n[5];
    wire COL6 = selected_columns_n[6];
    wire COL7 = selected_columns_n[7];

    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;
    wire pa_en_n;

    integer error_count;
    integer note_on_count0;
    integer note_on_count1;
    integer note_on_count2;
    integer note_on_count3;
    integer note_off_count0;
    integer note_off_count1;
    integer note_off_count2;
    integer note_off_count3;
    integer valid_samples;
    reg [3:0] nonselected_nonzero_seen;
    reg       four_nonzero_same_sample_seen;
    reg       stereo_left_nonzero_seen;
    reg       stereo_right_nonzero_seen;
    reg       stereo_distinct_seen;
    reg       chord_batch_seen;
    reg       pair_batch_seen;
    integer   env_early;
    integer   env_late;

    // Diode-isolated 4x8 matrix model.  Only the row actively driven low can
    // pull a pressed column low; all unselected rows are high impedance.
    assign selected_columns_n = (ROW0 === 1'b0) ? ~pressed[7:0]   :
                                (ROW1 === 1'b0) ? ~pressed[15:8]  :
                                (ROW2 === 1'b0) ? ~pressed[23:16] :
                                (ROW3 === 1'b0) ? ~pressed[31:24] :
                                                 8'hff;

    neo_four_string_matrix_audio_test_top #(
        .MATRIX_CLK_DIV        (2),
        .MATRIX_SETTLE_CYCLES  (1),
        .MATRIX_DEBOUNCE_FRAMES(2),
        .AUDIO_SAMPLE_DIV      (8),
        .PT8211_REF_DIV        (1),
        .CHORD_CAPTURE_SAMPLES (64),
        .PLUCK_ATTACK_SAMPLES  (4),
        .PLUCK_FAST_DECAY_SAMPLES(128),
        .PLUCK_FAST_SHIFT      (5),
        .PLUCK_SLOW_SHIFT      (6),
        .PLUCK_RELEASE_SHIFT   (2),
        .PLUCK_IDLE_LEVEL      (64)
    ) dut (
        .audio_clk_12m288(audio_clk_12m288),
        .rst_n            (rst_n),
        .ROW0             (ROW0),
        .ROW1             (ROW1),
        .ROW2             (ROW2),
        .ROW3             (ROW3),
        .COL0             (COL0),
        .COL1             (COL1),
        .COL2             (COL2),
        .COL3             (COL3),
        .COL4             (COL4),
        .COL5             (COL5),
        .COL6             (COL6),
        .COL7             (COL7),
        .dac_bclk         (dac_bclk),
        .dac_lrck         (dac_lrck),
        .dac_din          (dac_din),
        .pa_en_n          (pa_en_n)
    );

    always #1 audio_clk_12m288 = ~audio_clk_12m288;

    always @(posedge audio_clk_12m288) begin
        if (dut.note_on[0])  note_on_count0  = note_on_count0 + 1;
        if (dut.note_on[1])  note_on_count1  = note_on_count1 + 1;
        if (dut.note_on[2])  note_on_count2  = note_on_count2 + 1;
        if (dut.note_on[3])  note_on_count3  = note_on_count3 + 1;
        if (dut.note_off[0]) note_off_count0 = note_off_count0 + 1;
        if (dut.note_off[1]) note_off_count1 = note_off_count1 + 1;
        if (dut.note_off[2]) note_off_count2 = note_off_count2 + 1;
        if (dut.note_off[3]) note_off_count3 = note_off_count3 + 1;

        if (dut.note_on == 4'b1111)
            chord_batch_seen = 1'b1;
        if (dut.note_on == 4'b0101)
            pair_batch_seen = 1'b1;

        if (dut.voice_sample_valid && dut.voice_active == 4'b1111) begin
            valid_samples = valid_samples + 1;

            // Prove each voice produces PCM while another row is selected.
            // This fails if matrix scan state is incorrectly used as a voice
            // enable or PCM multiplexer.
            if ((ROW0 !== 1'b0) && (dut.voice_pcm0 != 24'sd0))
                nonselected_nonzero_seen[0] = 1'b1;
            if ((ROW1 !== 1'b0) && (dut.voice_pcm1 != 24'sd0))
                nonselected_nonzero_seen[1] = 1'b1;
            if ((ROW2 !== 1'b0) && (dut.voice_pcm2 != 24'sd0))
                nonselected_nonzero_seen[2] = 1'b1;
            if ((ROW3 !== 1'b0) && (dut.voice_pcm3 != 24'sd0))
                nonselected_nonzero_seen[3] = 1'b1;

            if ((dut.voice_pcm0 != 24'sd0) &&
                (dut.voice_pcm1 != 24'sd0) &&
                (dut.voice_pcm2 != 24'sd0) &&
                (dut.voice_pcm3 != 24'sd0))
                four_nonzero_same_sample_seen = 1'b1;
        end

        if (dut.pcm16_left_valid) begin
            if (dut.pcm16_left_out != 16'sd0)
                stereo_left_nonzero_seen = 1'b1;
            if (dut.pcm16_right_out != 16'sd0)
                stereo_right_nonzero_seen = 1'b1;
            if (dut.pcm16_left_out != dut.pcm16_right_out)
                stereo_distinct_seen = 1'b1;
        end
    end

    task wait_stable_fret;
        input [15:0] expected;
        integer guard;
        begin
            guard = 0;
            while (dut.stable_fret_id !== expected) begin
                @(posedge audio_clk_12m288);
                guard = guard + 1;
                if (guard > 1000) begin
                    $display("FAIL: stable fret timeout got=%h expected=%h",
                             dut.stable_fret_id, expected);
                    $finish;
                end
            end
        end
    endtask

    task wait_all_voices;
        integer guard;
        begin
            guard = 0;
            while (dut.voice_active !== 4'b1111) begin
                @(posedge audio_clk_12m288);
                guard = guard + 1;
                if (guard > 1000) begin
                    $display("FAIL: four voices did not become active");
                    $finish;
                end
            end
        end
    endtask

    initial begin
        audio_clk_12m288 = 1'b0;
        rst_n = 1'b0;
        pressed = 32'd0;

        error_count = 0;
        note_on_count0 = 0;
        note_on_count1 = 0;
        note_on_count2 = 0;
        note_on_count3 = 0;
        note_off_count0 = 0;
        note_off_count1 = 0;
        note_off_count2 = 0;
        note_off_count3 = 0;
        valid_samples = 0;
        nonselected_nonzero_seen = 4'b0000;
        four_nonzero_same_sample_seen = 1'b0;
        stereo_left_nonzero_seen = 1'b0;
        stereo_right_nonzero_seen = 1'b0;
        stereo_distinct_seen = 1'b0;
        chord_batch_seen = 1'b0;
        pair_batch_seen = 1'b0;
        env_early = 0;
        env_late = 0;

        repeat (6) @(posedge audio_clk_12m288);
        @(negedge audio_clk_12m288);
        rst_n = 1'b1;

        wait (dut.audio_rst_n === 1'b1);

        // Four simultaneous contacts:
        //   string 0 fret 1 = F4
        //   string 1 fret 6 = F4 (same phase increment, therefore no beat)
        //   string 2 fret 8 = D#4
        //   string 3 fret 4 = F#3
        // packed rows are {row3,row2,row1,row0}.
        pressed = 32'h08_80_20_01;
        wait_stable_fret(16'h4861);
        wait_all_voices();

        repeat (500) @(posedge audio_clk_12m288);

        if (!chord_batch_seen) begin
            $display("FAIL: four captured contacts did not share one note_on batch");
            error_count = error_count + 1;
        end

        if ((dut.voice_pan_right[0] == dut.voice_pan_right[1]) ||
            (dut.voice_pan_right[2] == dut.voice_pan_right[3])) begin
            $display("FAIL: four-voice dynamic pan plan was not balanced pan=%b",
                     dut.voice_pan_right);
            error_count = error_count + 1;
        end

        if (dut.phase_inc0 !== 32'h01DCD01D ||
            dut.phase_inc1 !== 32'h01DCD01D) begin
            $display("FAIL: equal F4 notes did not use equal phase increments");
            error_count = error_count + 1;
        end

        if (dut.voice_active !== 4'b1111) begin
            $display("FAIL: scan changed four-voice active state");
            error_count = error_count + 1;
        end

        if (nonselected_nonzero_seen !== 4'b1111) begin
            $display("FAIL: a voice was silent outside its scan row seen=%b",
                     nonselected_nonzero_seen);
            error_count = error_count + 1;
        end

        if (!four_nonzero_same_sample_seen) begin
            $display("FAIL: no sample contained four simultaneous PCM voices");
            error_count = error_count + 1;
        end


        if (!stereo_left_nonzero_seen || !stereo_right_nonzero_seen ||
            !stereo_distinct_seen) begin
            $display("FAIL: dynamic stereo mix was not independently active L=%b R=%b D=%b",
                     stereo_left_nonzero_seen, stereo_right_nonzero_seen,
                     stereo_distinct_seen);
            error_count = error_count + 1;
        end

        if ((note_on_count0 != 1) || (note_on_count1 != 1) ||
            (note_on_count2 != 1) || (note_on_count3 != 1)) begin
            $display("FAIL: scan retriggered note_on counts=%0d,%0d,%0d,%0d",
                     note_on_count0, note_on_count1,
                     note_on_count2, note_on_count3);
            error_count = error_count + 1;
        end

        // Change one selected fret without releasing that string.  Its phase
        // increment must change without a second Attack/note_on pulse.
        pressed = 32'h08_80_20_02;
        wait_stable_fret(16'h4862);
        repeat (100) @(posedge audio_clk_12m288);

        if (dut.phase_inc0 !== 32'h01F92A6D) begin
            $display("FAIL: string 0 fret change selected wrong phase increment");
            error_count = error_count + 1;
        end

        if ((note_on_count0 != 1) || (note_off_count0 != 0) ||
            (dut.voice_active !== 4'b1111)) begin
            $display("FAIL: fret change retriggered or interrupted string 0");
            error_count = error_count + 1;
        end

        // Release only string 2.  Other strings must remain continuously on.
        pressed = 32'h08_00_20_02;
        wait_stable_fret(16'h4062);
        repeat (100) @(posedge audio_clk_12m288);

        if (note_off_count2 != 1) begin
            $display("FAIL: string 2 did not receive one independent note_off");
            error_count = error_count + 1;
        end

        if ((dut.voice_active[3] !== 1'b1) ||
            (dut.voice_active[1] !== 1'b1) ||
            (dut.voice_active[0] !== 1'b1)) begin
            $display("FAIL: releasing string 2 disturbed another voice");
            error_count = error_count + 1;
        end

        if (pa_en_n !== 1'b0) begin
            $display("FAIL: amplifier disabled while voices were active");
            error_count = error_count + 1;
        end

        // The other held strings decay naturally without synthetic note_off
        // pulses.  Holding a fret must never produce another note_on.
        repeat (3000) @(posedge audio_clk_12m288);

        if ((note_off_count0 != 0) || (note_off_count1 != 0) ||
            (note_off_count2 != 1) || (note_off_count3 != 0)) begin
            $display("FAIL: natural decay generated unexpected note_off counts=%0d,%0d,%0d,%0d",
                     note_off_count0, note_off_count1,
                     note_off_count2, note_off_count3);
            error_count = error_count + 1;
        end

        if ((note_on_count0 != 1) || (note_on_count1 != 1) ||
            (note_on_count2 != 1) || (note_on_count3 != 1)) begin
            $display("FAIL: held fret retriggered natural pluck counts=%0d,%0d,%0d,%0d",
                     note_on_count0, note_on_count1,
                     note_on_count2, note_on_count3);
            error_count = error_count + 1;
        end

        if (dut.voice_active !== 4'b0000) begin
            $display("FAIL: natural pluck envelopes did not decay to idle active=%b",
                     dut.voice_active);
            error_count = error_count + 1;
        end

        if (pa_en_n !== 1'b0) begin
            $display("FAIL: amplifier was power-cycled when all envelopes became idle");
            error_count = error_count + 1;
        end

        // Prove that strings 0 and 2 (the old fixed left-channel pair) can be
        // pressed a little apart, captured as one chord, and assigned to
        // opposite primary channels.
        pressed = 32'd0;
        wait_stable_fret(16'h0000);
        repeat (20) @(posedge audio_clk_12m288);

        pressed = 32'h00_00_00_01;
        wait_stable_fret(16'h0001);
        repeat (32) @(posedge audio_clk_12m288);
        pressed = 32'h00_80_00_01;
        wait_stable_fret(16'h0801);

        wait (pair_batch_seen === 1'b1);
        wait (dut.voice_active[2:0] === 3'b101);

        if (dut.voice_pan_right[0] == dut.voice_pan_right[2]) begin
            $display("FAIL: strings 0/2 shared one primary channel pan=%b",
                     dut.voice_pan_right);
            error_count = error_count + 1;
        end

        // After the short Attack, the envelope must keep decreasing rather
        // than stop on an ADSR sustain plateau.
        repeat (12) @(posedge dut.sample_tick);
        env_early = dut.u_four_voice_audio_core.u_voice0.envelope_level;
        repeat (12) @(posedge dut.sample_tick);
        env_late = dut.u_four_voice_audio_core.u_voice0.envelope_level;
        if ((env_early <= env_late) || (env_late == 0)) begin
            $display("FAIL: pluck envelope did not decay naturally early=%0d late=%0d",
                     env_early, env_late);
            error_count = error_count + 1;
        end

        if ((note_on_count0 != 2) || (note_on_count1 != 1) ||
            (note_on_count2 != 2) || (note_on_count3 != 1)) begin
            $display("FAIL: staggered pair did not create one new event per voice counts=%0d,%0d,%0d,%0d",
                     note_on_count0, note_on_count1,
                     note_on_count2, note_on_count3);
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("PASS: 4x8 matrix selects four continuous simultaneous voices without scan-rate retrigger or gating");
            $display("PASS: equal F4 selections share one exact phase increment; only physical beat frequencies remain");
            $display("PASS: contacts inside the capture window launch on one audio event");
            $display("PASS: arbitrary first-pair voices use opposite hard-separated primary channels");
            $display("PASS: amplifier remains enabled between notes, avoiding per-note analogue startup pops");
            $display("PASS: held frets generate one fixed-velocity pluck with doubled natural decay and no sustain plateau");
        end
        else begin
            $display("FAIL: matrix four-voice test errors=%0d", error_count);
        end

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: matrix four-voice board test timed out");
        $finish;
    end

endmodule
