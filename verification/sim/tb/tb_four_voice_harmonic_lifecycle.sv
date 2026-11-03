`timescale 1ns/1ps

// FULL-path lifecycle test for four parallel 32-harmonic voices.
module tb_four_voice_harmonic_lifecycle;

    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_RELEASE = 3'd4;

    reg clk;
    reg rst_n;
    reg [3:0] dut_note_on;
    reg [3:0] dut_note_off;
    reg [3:0] ref_note_on;
    reg [3:0] ref_note_off;
    reg [7:0] velocity_level;
    reg [127:0] phase_inc;

    wire dut_sample_tick;
    wire dut_sample_valid;
    wire signed [23:0] dut_pcm_mix;
    wire [3:0] dut_voice_active;
    wire signed [95:0] dut_voice_pcm;
    wire [3:0] dut_voice_busy;
    wire [3:0] dut_deadline_miss;

    wire ref_sample_tick;
    wire ref_sample_valid;
    wire signed [23:0] ref_pcm_mix;
    wire [3:0] ref_voice_active;
    wire signed [95:0] ref_voice_pcm;
    wire [3:0] ref_voice_busy;
    wire [3:0] ref_deadline_miss;

    wire signed [23:0] dut_pcm0 = dut_voice_pcm[23:0];
    wire signed [23:0] dut_pcm1 = dut_voice_pcm[47:24];
    wire signed [23:0] dut_pcm2 = dut_voice_pcm[71:48];
    wire signed [23:0] dut_pcm3 = dut_voice_pcm[95:72];
    wire signed [23:0] ref_pcm0 = ref_voice_pcm[23:0];
    wire signed [23:0] ref_pcm1 = ref_voice_pcm[47:24];
    wire signed [23:0] ref_pcm2 = ref_voice_pcm[71:48];
    wire signed [23:0] ref_pcm3 = ref_voice_pcm[95:72];

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(64),
        .HARMONICS(32)
    ) u_dut (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (dut_note_on),
        .note_off     (dut_note_off),
        .velocity_level(velocity_level),
        .phase_inc    (phase_inc),
        .timbre_select(1'b0),
        .sustain_enable(1'b0),
        .sample_tick  (dut_sample_tick),
        .sample_valid (dut_sample_valid),
        .pcm_mix      (dut_pcm_mix),
        .voice_active (dut_voice_active),
        .voice_pcm    (dut_voice_pcm),
        .voice_busy   (dut_voice_busy),
        .deadline_miss(dut_deadline_miss),
        .timbre_blend (),
        .timbre_busy  ()
    );

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(64),
        .HARMONICS(32)
    ) u_ref (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (ref_note_on),
        .note_off     (ref_note_off),
        .velocity_level(velocity_level),
        .phase_inc    (phase_inc),
        .timbre_select(1'b0),
        .sustain_enable(1'b0),
        .sample_tick  (ref_sample_tick),
        .sample_valid (ref_sample_valid),
        .pcm_mix      (ref_pcm_mix),
        .voice_active (ref_voice_active),
        .voice_pcm    (ref_voice_pcm),
        .voice_busy   (ref_voice_busy),
        .deadline_miss(ref_deadline_miss),
        .timbre_blend (),
        .timbre_busy  ()
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
                0: dut_state = u_dut.u_voice0.u_voice_envelope.state;
                1: dut_state = u_dut.u_voice1.u_voice_envelope.state;
                2: dut_state = u_dut.u_voice2.u_voice_envelope.state;
                default: dut_state = u_dut.u_voice3.u_voice_envelope.state;
            endcase
        end
    endfunction

    function [2:0] ref_state;
        input integer voice_index;
        begin
            case (voice_index)
                0: ref_state = u_ref.u_voice0.u_voice_envelope.state;
                1: ref_state = u_ref.u_voice1.u_voice_envelope.state;
                2: ref_state = u_ref.u_voice2.u_voice_envelope.state;
                default: ref_state = u_ref.u_voice3.u_voice_envelope.state;
            endcase
        end
    endfunction

    function [15:0] dut_env;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_env = u_dut.u_voice0.u_voice_envelope.env_level;
                1: dut_env = u_dut.u_voice1.u_voice_envelope.env_level;
                2: dut_env = u_dut.u_voice2.u_voice_envelope.env_level;
                default: dut_env = u_dut.u_voice3.u_voice_envelope.env_level;
            endcase
        end
    endfunction

    function [15:0] ref_env;
        input integer voice_index;
        begin
            case (voice_index)
                0: ref_env = u_ref.u_voice0.u_voice_envelope.env_level;
                1: ref_env = u_ref.u_voice1.u_voice_envelope.env_level;
                2: ref_env = u_ref.u_voice2.u_voice_envelope.env_level;
                default: ref_env = u_ref.u_voice3.u_voice_envelope.env_level;
            endcase
        end
    endfunction

    function signed [15:0] dut_harmonic0_amplitude;
        input integer voice_index;
        begin
            case (voice_index)
                0: dut_harmonic0_amplitude = u_dut.u_voice0.harmonic_amplitude[0];
                1: dut_harmonic0_amplitude = u_dut.u_voice1.harmonic_amplitude[0];
                2: dut_harmonic0_amplitude = u_dut.u_voice2.harmonic_amplitude[0];
                default:
                   dut_harmonic0_amplitude = u_dut.u_voice3.harmonic_amplitude[0];
            endcase
        end
    endfunction

    task pulse_both;
        input [3:0] on_value;
        begin
            @(negedge clk);
            dut_note_on = on_value;
            ref_note_on = on_value;
            @(negedge clk);
            dut_note_on = 4'd0;
            ref_note_on = 4'd0;
            #1;
        end
    endtask

    task pulse_dut;
        input [3:0] on_value;
        input [3:0] off_value;
        begin
            @(negedge clk);
            dut_note_on = on_value;
            dut_note_off = off_value;
            @(negedge clk);
            dut_note_on = 4'd0;
            dut_note_off = 4'd0;
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
                $display("FAIL: harmonic voice %0d state timeout got=%0d expected=%0d",
                         voice_index, dut_state(voice_index), expected_state);
                $finish;
            end
        end
    endtask

    task release_voice;
        input [3:0] voice_mask;
        input integer voice_index;
        begin
            comparison_disabled[voice_index] = 1'b1;
            monitor_release[voice_index] = 1'b1;
            pulse_dut(4'd0, voice_mask);
            wait_for_state(voice_index, STATE_RELEASE, 4);
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
                $display("FAIL: harmonic DUT/reference sample misalignment");
                $finish;
            end
            if ((dut_deadline_miss !== 4'd0) ||
                (ref_deadline_miss !== 4'd0) ||
                (dut_voice_busy !== 4'd0) || (ref_voice_busy !== 4'd0)) begin
                $display("FAIL: harmonic deadline/busy sample=%0d miss=%b/%b busy=%b/%b",
                         sample_count, dut_deadline_miss, ref_deadline_miss,
                         dut_voice_busy, ref_voice_busy);
                $finish;
            end
            if (dut_pcm_mix !== sat_mix4(dut_pcm0, dut_pcm1,
                                         dut_pcm2, dut_pcm3)) begin
                $display("FAIL: harmonic lifecycle mixer mismatch sample=%0d",
                         sample_count);
                $finish;
            end
            mix_check_count = mix_check_count + 1;

            if (dut_pcm0 !== 24'sd0) nonzero_seen[0] = 1'b1;
            if (dut_pcm1 !== 24'sd0) nonzero_seen[1] = 1'b1;
            if (dut_pcm2 !== 24'sd0) nonzero_seen[2] = 1'b1;
            if (dut_pcm3 !== 24'sd0) nonzero_seen[3] = 1'b1;

            if (!comparison_disabled[0] &&
                ((dut_pcm0 !== ref_pcm0) ||
                 (dut_voice_active[0] !== ref_voice_active[0]) ||
                 (dut_env(0) !== ref_env(0)) ||
                 (dut_state(0) !== ref_state(0)))) begin
                $display("FAIL: harmonic voice 0 isolation");
                $finish;
            end
            if (!comparison_disabled[1] &&
                ((dut_pcm1 !== ref_pcm1) ||
                 (dut_voice_active[1] !== ref_voice_active[1]) ||
                 (dut_env(1) !== ref_env(1)) ||
                 (dut_state(1) !== ref_state(1)))) begin
                $display("FAIL: harmonic voice 1 isolation");
                $finish;
            end
            if (!comparison_disabled[2] &&
                ((dut_pcm2 !== ref_pcm2) ||
                 (dut_voice_active[2] !== ref_voice_active[2]) ||
                 (dut_env(2) !== ref_env(2)) ||
                 (dut_state(2) !== ref_state(2)))) begin
                $display("FAIL: harmonic voice 2 isolation");
                $finish;
            end
            if (!comparison_disabled[3] &&
                ((dut_pcm3 !== ref_pcm3) ||
                 (dut_voice_active[3] !== ref_voice_active[3]) ||
                 (dut_env(3) !== ref_env(3)) ||
                 (dut_state(3) !== ref_state(3)))) begin
                $display("FAIL: harmonic voice 3 isolation");
                $finish;
            end

            if (monitor_release[0] && dut_voice_active[0] &&
                (dut_state(0) == STATE_RELEASE) &&
                (dut_env(0) > previous_env0)) begin
                $display("FAIL: harmonic voice 0 Release increased");
                $finish;
            end
            if (monitor_release[1] && dut_voice_active[1] &&
                (dut_state(1) == STATE_RELEASE) &&
                (dut_env(1) > previous_env1)) begin
                $display("FAIL: harmonic voice 1 Release increased");
                $finish;
            end
            if (monitor_release[2] && dut_voice_active[2] &&
                (dut_state(2) == STATE_RELEASE) &&
                (dut_env(2) > previous_env2)) begin
                $display("FAIL: harmonic voice 2 Release increased");
                $finish;
            end
            if (monitor_release[3] && dut_voice_active[3] &&
                (dut_state(3) == STATE_RELEASE) &&
                (dut_env(3) > previous_env3)) begin
                $display("FAIL: harmonic voice 3 Release increased");
                $finish;
            end

            previous_env0 = dut_env(0);
            previous_env1 = dut_env(1);
            previous_env2 = dut_env(2);
            previous_env3 = dut_env(3);
        end
    end

    integer guard;
    reg signed [15:0] amplitude_before_retrigger;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        dut_note_on = 4'd0;
        dut_note_off = 4'd0;
        ref_note_on = 4'd0;
        ref_note_off = 4'd0;
        velocity_level = 8'hE4;
        phase_inc = {
            32'h012C5F93, 32'h0151285D,
            32'h017A725A, 32'h01DCD01D
        };
        comparison_disabled = 4'd0;
        monitor_release = 4'd0;
        nonzero_seen = 4'd0;
        sample_count = 0;
        mix_check_count = 0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        pulse_both(4'b1111);
        guard = 0;
        while (((dut_voice_active !== 4'b1111) ||
                (ref_voice_active !== 4'b1111)) && (guard < 8)) begin
            wait_next_sample;
            guard = guard + 1;
        end
        if ((dut_voice_active !== 4'b1111) ||
            (ref_voice_active !== 4'b1111)) begin
            $display("FAIL: four harmonic lifecycle voices did not start");
            $finish;
        end

        wait_samples(48);
        if (nonzero_seen !== 4'b1111) begin
            $display("FAIL: harmonic lifecycle nonzero mask=%b", nonzero_seen);
            $finish;
        end

        release_voice(4'b0100, 2);
        wait_samples(12);
        amplitude_before_retrigger = dut_harmonic0_amplitude(2);
        if ((dut_state(2) !== STATE_RELEASE) ||
            (dut_env(2) == 0)) begin
            $display("FAIL: harmonic voice 2 was not in Release before retrigger");
            $finish;
        end

        monitor_release[2] = 1'b0;
        pulse_dut(4'b0100, 4'd0);
        wait_for_state(2, STATE_ATTACK, 4);
        if ((dut_voice_active[2] !== 1'b1) ||
            (dut_harmonic0_amplitude(2) <= amplitude_before_retrigger)) begin
            $display("FAIL: harmonic voice 2 retrigger did not reload Attack/harmonics");
            $finish;
        end

        wait_samples(9);
        release_voice(4'b0100, 2);
        wait_samples(13);
        release_voice(4'b0001, 0);
        wait_samples(17);
        release_voice(4'b1000, 3);
        wait_samples(21);
        release_voice(4'b0010, 1);

        guard = 0;
        while ((dut_voice_active !== 4'b0000) && (guard < 18000)) begin
            wait_next_sample;
            guard = guard + 1;
        end

        if (dut_voice_active !== 4'b0000) begin
            $display("FAIL: harmonic lifecycle Release timeout active=%b",
                     dut_voice_active);
            $finish;
        end
        if ((dut_env(0) !== 16'd0) || (dut_env(1) !== 16'd0) ||
            (dut_env(2) !== 16'd0) || (dut_env(3) !== 16'd0)) begin
            $display("FAIL: harmonic lifecycle envelopes did not reach zero");
            $finish;
        end
        if (ref_voice_active !== 4'b1111) begin
            $display("FAIL: harmonic reference voices stopped unexpectedly");
            $finish;
        end
        if ((dut_deadline_miss !== 4'd0) ||
            (ref_deadline_miss !== 4'd0) ||
            (mix_check_count < 10000)) begin
            $display("FAIL: harmonic lifecycle final deadline/check count");
            $finish;
        end

        $display("PASS: four 32-harmonic voices staggered release, isolation, retrigger and deadlines samples=%0d",
                 mix_check_count);
        $finish;
    end

endmodule
