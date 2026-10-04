`timescale 1ns/1ps

// Full four-voice lifecycle integration test.
//
// The DUT receives staggered releases and a retrigger during Release.  A
// second, otherwise identical reference chain keeps all four voices sounding.
// Voices that have not been released must remain bit-for-bit identical to the
// reference chain, proving that another string's lifecycle events cannot
// disturb their phase, envelope, active state, or PCM output.
module tb_four_voice_lifecycle;

    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_RELEASE = 3'd4;

    reg         clk;
    reg         rst_n;

    reg         dut_stable_valid;
    reg [15:0]  dut_stable_fret_id;
    reg [3:0]   dut_pluck_valid;

    reg         ref_stable_valid;
    reg [15:0]  ref_stable_fret_id;
    reg [3:0]   ref_pluck_valid;

    reg [7:0]   velocity_level;

    wire [3:0]   dut_note_on;
    wire [3:0]   dut_note_off;
    wire [3:0]   dut_control_active;
    wire [127:0] dut_target_phase_inc;
    wire [127:0] dut_phase_inc;
    wire         dut_sample_tick;
    wire         dut_sample_valid;
    wire signed [23:0] dut_pcm_mix;
    wire [3:0]   dut_audio_active;
    wire signed [95:0] dut_voice_pcm;

    wire [3:0]   ref_note_on;
    wire [3:0]   ref_note_off;
    wire [3:0]   ref_control_active;
    wire [127:0] ref_target_phase_inc;
    wire [127:0] ref_phase_inc;
    wire         ref_sample_tick;
    wire         ref_sample_valid;
    wire signed [23:0] ref_pcm_mix;
    wire [3:0]   ref_audio_active;
    wire signed [95:0] ref_voice_pcm;

    wire signed [23:0] dut_pcm0 = dut_voice_pcm[23:0];
    wire signed [23:0] dut_pcm1 = dut_voice_pcm[47:24];
    wire signed [23:0] dut_pcm2 = dut_voice_pcm[71:48];
    wire signed [23:0] dut_pcm3 = dut_voice_pcm[95:72];

    wire signed [23:0] ref_pcm0 = ref_voice_pcm[23:0];
    wire signed [23:0] ref_pcm1 = ref_voice_pcm[47:24];
    wire signed [23:0] ref_pcm2 = ref_voice_pcm[71:48];
    wire signed [23:0] ref_pcm3 = ref_voice_pcm[95:72];

    four_string_voice_control #(
        .SLIDE_SAMPLES(4), .VIBRATO_EXIT_INTERVAL(0)
    ) u_dut_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .stable_valid    (dut_stable_valid),
        .stable_fret_id  (dut_stable_fret_id),
        .pluck_valid     (dut_pluck_valid),
        .sample_ce       (dut_sample_tick),
        .note_on         (dut_note_on),
        .note_off        (dut_note_off),
        .slide_valid     (),
        .vibrato_enable(),
        .voice_active    (dut_control_active),
        .current_fret_id (),
        .target_phase_inc(dut_target_phase_inc),
        .phase_inc       (dut_phase_inc),
        .slide_busy      ()
    );

    four_voice_audio_core #(
        .SAMPLE_DIV(4)
    ) u_dut_audio (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (dut_note_on),
        .note_off     (dut_note_off),
        .velocity_level(velocity_level),
        .phase_inc    (dut_phase_inc),
        .sample_tick  (dut_sample_tick),
        .sample_valid (dut_sample_valid),
        .pcm_mix      (dut_pcm_mix),
        .voice_active (dut_audio_active),
        .voice_pcm    (dut_voice_pcm)
    );

    four_string_voice_control #(
        .SLIDE_SAMPLES(4), .VIBRATO_EXIT_INTERVAL(0)
    ) u_ref_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .stable_valid    (ref_stable_valid),
        .stable_fret_id  (ref_stable_fret_id),
        .pluck_valid     (ref_pluck_valid),
        .sample_ce       (ref_sample_tick),
        .note_on         (ref_note_on),
        .note_off        (ref_note_off),
        .slide_valid     (),
        .vibrato_enable(),
        .voice_active    (ref_control_active),
        .current_fret_id (),
        .target_phase_inc(ref_target_phase_inc),
        .phase_inc       (ref_phase_inc),
        .slide_busy      ()
    );

    four_voice_audio_core #(
        .SAMPLE_DIV(4)
    ) u_ref_audio (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (ref_note_on),
        .note_off     (ref_note_off),
        .velocity_level(velocity_level),
        .phase_inc    (ref_phase_inc),
        .sample_tick  (ref_sample_tick),
        .sample_valid (ref_sample_valid),
        .pcm_mix      (ref_pcm_mix),
        .voice_active (ref_audio_active),
        .voice_pcm    (ref_voice_pcm)
    );

    always #5 clk = ~clk;

    function signed [23:0] sat_mix4;
        input signed [23:0] a;
        input signed [23:0] b;
        input signed [23:0] c;
        input signed [23:0] d;
        reg signed [25:0] sum;
        begin
            sum = $signed({{2{a[23]}}, a}) +
                  $signed({{2{b[23]}}, b}) +
                  $signed({{2{c[23]}}, c}) +
                  $signed({{2{d[23]}}, d});

            if (sum > 26'sd8388607)
                sat_mix4 = 24'sh7fffff;
            else if (sum < -26'sd8388608)
                sat_mix4 = 24'sh800000;
            else
                sat_mix4 = sum[23:0];
        end
    endfunction

    function [2:0] dut_state;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_state = u_dut_audio.u_voice0.u_voice_envelope.state;
                1: dut_state = u_dut_audio.u_voice1.u_voice_envelope.state;
                2: dut_state = u_dut_audio.u_voice2.u_voice_envelope.state;
                default:
                   dut_state = u_dut_audio.u_voice3.u_voice_envelope.state;
            endcase
        end
    endfunction

    function [2:0] ref_state;
        input integer voice_index;
        begin
            case (voice_index)
                0: ref_state = u_ref_audio.u_voice0.u_voice_envelope.state;
                1: ref_state = u_ref_audio.u_voice1.u_voice_envelope.state;
                2: ref_state = u_ref_audio.u_voice2.u_voice_envelope.state;
                default:
                   ref_state = u_ref_audio.u_voice3.u_voice_envelope.state;
            endcase
        end
    endfunction

    function [15:0] dut_env;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_env = u_dut_audio.u_voice0.u_voice_envelope.env_level;
                1: dut_env = u_dut_audio.u_voice1.u_voice_envelope.env_level;
                2: dut_env = u_dut_audio.u_voice2.u_voice_envelope.env_level;
                default:
                   dut_env = u_dut_audio.u_voice3.u_voice_envelope.env_level;
            endcase
        end
    endfunction

    function [15:0] ref_env;
        input integer voice_index;
        begin
            case (voice_index)
                0: ref_env = u_ref_audio.u_voice0.u_voice_envelope.env_level;
                1: ref_env = u_ref_audio.u_voice1.u_voice_envelope.env_level;
                2: ref_env = u_ref_audio.u_voice2.u_voice_envelope.env_level;
                default:
                   ref_env = u_ref_audio.u_voice3.u_voice_envelope.env_level;
            endcase
        end
    endfunction

    function [31:0] dut_target_phase;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_target_phase = dut_target_phase_inc[31:0];
                1: dut_target_phase = dut_target_phase_inc[63:32];
                2: dut_target_phase = dut_target_phase_inc[95:64];
                default: dut_target_phase = dut_target_phase_inc[127:96];
            endcase
        end
    endfunction

    function [31:0] dut_current_phase;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_current_phase = dut_phase_inc[31:0];
                1: dut_current_phase = dut_phase_inc[63:32];
                2: dut_current_phase = dut_phase_inc[95:64];
                default: dut_current_phase = dut_phase_inc[127:96];
            endcase
        end
    endfunction

    task pulse_stable_both;
        input [15:0] fret_value;
        begin
            @(negedge clk);
            dut_stable_fret_id = fret_value;
            ref_stable_fret_id = fret_value;
            dut_stable_valid = 1'b1;
            ref_stable_valid = 1'b1;
            @(negedge clk);
            dut_stable_valid = 1'b0;
            ref_stable_valid = 1'b0;
            #1;
        end
    endtask

    task pulse_stable_dut;
        input [15:0] fret_value;
        begin
            @(negedge clk);
            dut_stable_fret_id = fret_value;
            dut_stable_valid = 1'b1;
            @(negedge clk);
            dut_stable_valid = 1'b0;
            #1;
        end
    endtask

    task pulse_pluck_both;
        input [3:0] pluck_value;
        begin
            @(negedge clk);
            dut_pluck_valid = pluck_value;
            ref_pluck_valid = pluck_value;
            @(negedge clk);
            dut_pluck_valid = 4'd0;
            ref_pluck_valid = 4'd0;
            #1;
        end
    endtask

    task pulse_pluck_dut;
        input [3:0] pluck_value;
        begin
            @(negedge clk);
            dut_pluck_valid = pluck_value;
            @(negedge clk);
            dut_pluck_valid = 4'd0;
            #1;
        end
    endtask

    integer sample_count;
    integer mix_check_count;
    reg [3:0] nonzero_seen;
    reg [3:0] comparison_disabled;
    reg [3:0] monitor_release;
    reg [15:0] previous_env0;
    reg [15:0] previous_env1;
    reg [15:0] previous_env2;
    reg [15:0] previous_env3;

    task wait_next_sample;
        integer starting_count;
        begin
            starting_count = sample_count;
            while (sample_count == starting_count)
                @(posedge clk);
            #1;
        end
    endtask

    task wait_samples;
        input integer count;
        integer k;
        begin
            for (k = 0; k < count; k = k + 1)
                wait_next_sample;
        end
    endtask

    task wait_for_state;
        input integer voice_index;
        input [2:0] expected_state;
        input integer maximum_samples;
        integer guard;
        begin
            guard = 0;
            while ((dut_state(voice_index) !== expected_state) &&
                   (guard < maximum_samples)) begin
                wait_next_sample;
                guard = guard + 1;
            end

            if (dut_state(voice_index) !== expected_state) begin
                $display("FAIL: voice %0d state timeout got=%0d expected=%0d",
                         voice_index, dut_state(voice_index), expected_state);
                $finish;
            end
        end
    endtask

    task release_voice;
        input [15:0] new_fret_state;
        input [3:0] expected_note_off;
        input integer voice_index;
        reg [31:0] held_target;
        reg [31:0] held_phase;
        begin
            held_target = dut_target_phase(voice_index);
            held_phase  = dut_current_phase(voice_index);

            pulse_stable_dut(new_fret_state);

            if (dut_note_off !== expected_note_off) begin
                $display("FAIL: voice %0d note_off=%b expected=%b",
                         voice_index, dut_note_off, expected_note_off);
                $finish;
            end
            if (dut_control_active[voice_index] !== 1'b0) begin
                $display("FAIL: voice %0d controller remained active",
                         voice_index);
                $finish;
            end
            if ((dut_target_phase(voice_index) !== held_target) ||
                (dut_current_phase(voice_index) !== held_phase)) begin
                $display("FAIL: voice %0d changed pitch on final fret release",
                         voice_index);
                $finish;
            end

            comparison_disabled[voice_index] = 1'b1;
            monitor_release[voice_index] = 1'b1;

            wait_for_state(voice_index, STATE_RELEASE, 4);

            if (dut_target_phase(voice_index) !== held_target) begin
                $display("FAIL: voice %0d release did not hold phase target",
                         voice_index);
                $finish;
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            sample_count = 0;
            mix_check_count = 0;
            nonzero_seen = 4'd0;
            previous_env0 = 16'd0;
            previous_env1 = 16'd0;
            previous_env2 = 16'd0;
            previous_env3 = 16'd0;
        end
        else if (dut_sample_valid) begin
            sample_count = sample_count + 1;

            if (ref_sample_valid !== 1'b1) begin
                $display("FAIL: DUT/reference sample_valid misalignment");
                $finish;
            end

            if (dut_pcm_mix !== sat_mix4(dut_pcm0, dut_pcm1,
                                         dut_pcm2, dut_pcm3)) begin
                $display("FAIL: lifecycle mixer mismatch sample=%0d mix=%0d expected=%0d",
                         sample_count, dut_pcm_mix,
                         sat_mix4(dut_pcm0, dut_pcm1, dut_pcm2, dut_pcm3));
                $finish;
            end
            mix_check_count = mix_check_count + 1;

            if (dut_pcm0 !== 24'sd0) nonzero_seen[0] = 1'b1;
            if (dut_pcm1 !== 24'sd0) nonzero_seen[1] = 1'b1;
            if (dut_pcm2 !== 24'sd0) nonzero_seen[2] = 1'b1;
            if (dut_pcm3 !== 24'sd0) nonzero_seen[3] = 1'b1;

            if (!comparison_disabled[0] &&
                ((dut_pcm0 !== ref_pcm0) ||
                 (dut_audio_active[0] !== ref_audio_active[0]) ||
                 (dut_env(0) !== ref_env(0)) ||
                 (dut_state(0) !== ref_state(0)))) begin
                $display("FAIL: voice 0 changed after another voice event");
                $finish;
            end
            if (!comparison_disabled[1] &&
                ((dut_pcm1 !== ref_pcm1) ||
                 (dut_audio_active[1] !== ref_audio_active[1]) ||
                 (dut_env(1) !== ref_env(1)) ||
                 (dut_state(1) !== ref_state(1)))) begin
                $display("FAIL: voice 1 changed after another voice event");
                $finish;
            end
            if (!comparison_disabled[2] &&
                ((dut_pcm2 !== ref_pcm2) ||
                 (dut_audio_active[2] !== ref_audio_active[2]) ||
                 (dut_env(2) !== ref_env(2)) ||
                 (dut_state(2) !== ref_state(2)))) begin
                $display("FAIL: voice 2 changed after another voice event");
                $finish;
            end
            if (!comparison_disabled[3] &&
                ((dut_pcm3 !== ref_pcm3) ||
                 (dut_audio_active[3] !== ref_audio_active[3]) ||
                 (dut_env(3) !== ref_env(3)) ||
                 (dut_state(3) !== ref_state(3)))) begin
                $display("FAIL: voice 3 changed after another voice event");
                $finish;
            end

            if (monitor_release[0] && dut_audio_active[0] &&
                (dut_state(0) == STATE_RELEASE) &&
                (dut_env(0) > previous_env0)) begin
                $display("FAIL: voice 0 Release envelope increased");
                $finish;
            end
            if (monitor_release[1] && dut_audio_active[1] &&
                (dut_state(1) == STATE_RELEASE) &&
                (dut_env(1) > previous_env1)) begin
                $display("FAIL: voice 1 Release envelope increased");
                $finish;
            end
            if (monitor_release[2] && dut_audio_active[2] &&
                (dut_state(2) == STATE_RELEASE) &&
                (dut_env(2) > previous_env2)) begin
                $display("FAIL: voice 2 Release envelope increased");
                $finish;
            end
            if (monitor_release[3] && dut_audio_active[3] &&
                (dut_state(3) == STATE_RELEASE) &&
                (dut_env(3) > previous_env3)) begin
                $display("FAIL: voice 3 Release envelope increased");
                $finish;
            end

            previous_env0 = dut_env(0);
            previous_env1 = dut_env(1);
            previous_env2 = dut_env(2);
            previous_env3 = dut_env(3);
        end
    end

    integer guard;
    integer release_sample2_first;
    integer retrigger_sample2;
    integer release_sample2_second;
    integer release_sample0;
    integer release_sample3;
    integer release_sample1;
    reg [15:0] env2_before_retrigger;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        dut_stable_valid = 1'b0;
        dut_stable_fret_id = 16'h0000;
        dut_pluck_valid = 4'd0;
        ref_stable_valid = 1'b0;
        ref_stable_fret_id = 16'h0000;
        ref_pluck_valid = 4'd0;

        // String 0..3 use velocity levels 0, 1, 2, and 3 respectively.
        velocity_level = 8'hE4;
        comparison_disabled = 4'd0;
        monitor_release = 4'd0;
        nonzero_seen = 4'd0;
        sample_count = 0;
        mix_check_count = 0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        // Four distinct pitches: frets 1, 2, 4, and 7.
        pulse_stable_both(16'h7421);
        wait_samples(2);

        if ((dut_target_phase_inc[31:0]   !== 32'h01DCD01D) ||
            (dut_target_phase_inc[63:32]  !== 32'h017A725A) ||
            (dut_target_phase_inc[95:64]  !== 32'h0151285D) ||
            (dut_target_phase_inc[127:96] !== 32'h012C5F93) ||
            (dut_phase_inc !== dut_target_phase_inc) ||
            (ref_phase_inc !== ref_target_phase_inc)) begin
            $display("FAIL: lifecycle initial pitch selection");
            $finish;
        end

        pulse_pluck_both(4'b1111);
        guard = 0;
        while (((dut_audio_active !== 4'b1111) ||
                (ref_audio_active !== 4'b1111)) && (guard < 8)) begin
            wait_next_sample;
            guard = guard + 1;
        end
        if ((dut_audio_active !== 4'b1111) ||
            (ref_audio_active !== 4'b1111)) begin
            $display("FAIL: four lifecycle voices did not start together");
            $finish;
        end

        // Let every voice produce nonzero PCM and leave Attack.
        wait_samples(48);
        if (nonzero_seen !== 4'b1111) begin
            $display("FAIL: lifecycle voice PCM nonzero mask=%b",
                     nonzero_seen);
            $finish;
        end

        // Release voice 2 first, then retrigger it while its audio envelope is
        // still in Release.  Selecting fret 5 while the controller is inactive
        // must update pitch without generating another note event.
        release_sample2_first = sample_count;
        release_voice(16'h7021, 4'b0100, 2);
        wait_samples(20);
        env2_before_retrigger = dut_env(2);
        if ((dut_state(2) !== STATE_RELEASE) ||
            (env2_before_retrigger == 0)) begin
            $display("FAIL: voice 2 was not active in Release before retrigger");
            $finish;
        end

        pulse_stable_dut(16'h7521);
        if ((dut_note_on !== 4'd0) || (dut_note_off !== 4'd0) ||
            (dut_target_phase_inc[95:64] !== 32'h016534C3)) begin
            $display("FAIL: inactive voice 2 pitch selection before retrigger");
            $finish;
        end

        monitor_release[2] = 1'b0;
        pulse_pluck_dut(4'b0100);
        retrigger_sample2 = sample_count;
        wait_for_state(2, STATE_ATTACK, 4);
        if ((dut_control_active[2] !== 1'b1) ||
            (dut_audio_active[2] !== 1'b1) ||
            (dut_env(2) >= env2_before_retrigger)) begin
            $display("FAIL: voice 2 did not restart Attack during Release");
            $finish;
        end

        wait_samples(12);
        release_sample2_second = sample_count;
        release_voice(16'h7021, 4'b0100, 2);

        wait_samples(17);
        release_sample0 = sample_count;
        release_voice(16'h7020, 4'b0001, 0);

        wait_samples(23);
        release_sample3 = sample_count;
        release_voice(16'h0020, 4'b1000, 3);

        wait_samples(29);
        release_sample1 = sample_count;
        release_voice(16'h0000, 4'b0010, 1);

        if (!((release_sample2_first < retrigger_sample2) &&
              (retrigger_sample2 < release_sample2_second) &&
              (release_sample2_second < release_sample0) &&
              (release_sample0 < release_sample3) &&
              (release_sample3 < release_sample1))) begin
            $display("FAIL: lifecycle events were not staggered");
            $finish;
        end

        // Use the real configured envelope lengths.  The slowest velocity-3
        // voice needs fewer than 17000 samples to reach IDLE from full scale.
        guard = 0;
        while ((dut_audio_active !== 4'b0000) && (guard < 18000)) begin
            wait_next_sample;
            guard = guard + 1;
        end

        if (dut_audio_active !== 4'b0000) begin
            $display("FAIL: lifecycle Release timeout active=%b env=%0d/%0d/%0d/%0d",
                     dut_audio_active, dut_env(0), dut_env(1),
                     dut_env(2), dut_env(3));
            $finish;
        end
        if ((dut_env(0) !== 16'd0) || (dut_env(1) !== 16'd0) ||
            (dut_env(2) !== 16'd0) || (dut_env(3) !== 16'd0)) begin
            $display("FAIL: lifecycle envelopes did not return to zero");
            $finish;
        end
        if (ref_audio_active !== 4'b1111) begin
            $display("FAIL: reference voices did not remain active");
            $finish;
        end
        if (mix_check_count < 10000) begin
            $display("FAIL: insufficient lifecycle mixer checks=%0d",
                     mix_check_count);
            $finish;
        end

        $display("PASS: four-voice staggered release, isolation, retrigger and saturated mix samples=%0d",
                 mix_check_count);
        $finish;
    end

endmodule
