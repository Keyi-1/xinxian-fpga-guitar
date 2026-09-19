`timescale 1ns/1ps

module tb_harmonic_velocity_profiles;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg note_on;

    harmonic_voice_core #(.HARMONICS(32)) u_v0 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(1'b0), .velocity_level(2'd0),
        .phase_inc(32'h01c20d2f), .timbre_blend(9'd0),
        .sustain_enable(1'b0), .sample_valid(), .pcm_out(), .env_level(),
        .active(), .busy(), .deadline_miss()
    );
    harmonic_voice_core #(.HARMONICS(32)) u_v1 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(1'b0), .velocity_level(2'd1),
        .phase_inc(32'h01c20d2f), .timbre_blend(9'd0),
        .sustain_enable(1'b0), .sample_valid(), .pcm_out(), .env_level(),
        .active(), .busy(), .deadline_miss()
    );
    harmonic_voice_core #(.HARMONICS(32)) u_v2 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(1'b0), .velocity_level(2'd2),
        .phase_inc(32'h01c20d2f), .timbre_blend(9'd0),
        .sustain_enable(1'b0), .sample_valid(), .pcm_out(), .env_level(),
        .active(), .busy(), .deadline_miss()
    );
    harmonic_voice_core #(.HARMONICS(32)) u_v3 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(1'b0), .velocity_level(2'd3),
        .phase_inc(32'h01c20d2f), .timbre_blend(9'd0),
        .sustain_enable(1'b0), .sample_valid(), .pcm_out(), .env_level(),
        .active(), .busy(), .deadline_miss()
    );

    always #5 clk = ~clk;

    integer low_soft;
    integer low_hard;
    integer high_soft;
    integer high_hard;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_ce = 1'b0;
        note_on = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        @(negedge clk);
        sample_ce = 1'b1;
        note_on = 1'b1;
        @(posedge clk);
        #1;

        low_soft = u_v0.harmonic_amplitude[0];
        low_hard = u_v3.harmonic_amplitude[0];
        high_soft = u_v0.harmonic_amplitude[8];
        high_hard = u_v3.harmonic_amplitude[8];

        if (!((u_v0.harmonic_amplitude[0] < u_v1.harmonic_amplitude[0]) &&
              (u_v1.harmonic_amplitude[0] < u_v2.harmonic_amplitude[0]) &&
              (u_v2.harmonic_amplitude[0] < u_v3.harmonic_amplitude[0]))) begin
            $display("FAIL: low harmonic velocity levels are not ordered");
            $finish;
        end
        if (!((u_v0.harmonic_amplitude[8] < u_v1.harmonic_amplitude[8]) &&
              (u_v1.harmonic_amplitude[8] < u_v2.harmonic_amplitude[8]) &&
              (u_v2.harmonic_amplitude[8] < u_v3.harmonic_amplitude[8]))) begin
            $display("FAIL: high harmonic velocity levels are not ordered");
            $finish;
        end
        if ((high_hard * low_soft) <= (high_soft * low_hard)) begin
            $display("FAIL: hard pluck did not increase high/low harmonic ratio");
            $finish;
        end
        if (u_v3.harmonic_amplitude_rock[8] <=
            u_v3.harmonic_amplitude[8]) begin
            $display("FAIL: rock profile did not emphasize high harmonics");
            $finish;
        end
        if (!((u_v3.harmonic_decay[0] > u_v3.harmonic_decay[8]) &&
              (u_v3.harmonic_decay_rock[0] >
               u_v3.harmonic_decay_rock[8]))) begin
            $display("FAIL: per-harmonic decay coefficients are not distinct");
            $finish;
        end

        $display("PASS: classic/rock four-level harmonic excitation and independent decay profiles");
        $finish;
    end

endmodule
