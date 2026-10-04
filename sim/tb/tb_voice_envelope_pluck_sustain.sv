`timescale 1ns/1ps
module tb_voice_envelope_pluck_sustain;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, note_on = 0, note_off = 0, sustain = 1;
    wire [15:0] normal_level, sustain_level;
    wire normal_active, sustain_active;
    voice_envelope #(.PLUCK_MODE(1), .PLUCK_ATTACK_SAMPLES(4),
                     .PLUCK_RELEASE_SHIFT(4)) normal (
        .clk(clk), .rst_n(rst_n), .sample_ce(1'b1),
        .note_on(note_on), .note_off(note_off), .velocity_level(2'd3),
        .sustain_enable(1'b0), .env_level(normal_level), .active(normal_active)
    );
    voice_envelope #(.PLUCK_MODE(1), .PLUCK_ATTACK_SAMPLES(4),
                     .PLUCK_RELEASE_SHIFT(4)) extended (
        .clk(clk), .rst_n(rst_n), .sample_ce(1'b1),
        .note_on(note_on), .note_off(note_off), .velocity_level(2'd3),
        .sustain_enable(sustain), .env_level(sustain_level), .active(sustain_active)
    );
    integer normal_idle = 0, sustain_idle = 0, n;
    reg [15:0] previous_normal, previous_sustain;
    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        note_on = 1;
        @(negedge clk); note_on = 0;
        repeat (8) @(negedge clk);
        if (normal_level != sustain_level || normal_level == 0)
            $fatal(1, "FAIL: pluck sustain changed Attack");
        note_off = 1;
        @(negedge clk); note_off = 0;
        sustain = 0; // The chosen Release speed must remain latched.
        previous_normal = normal_level; previous_sustain = sustain_level;
        for (n = 1; n <= 1000; n = n + 1) begin
            @(negedge clk);
            if (normal_level > previous_normal || sustain_level > previous_sustain)
                $fatal(1, "FAIL: pluck Release is not monotonic");
            if (!normal_active && normal_idle == 0) normal_idle = n;
            if (!sustain_active && sustain_idle == 0) sustain_idle = n;
            previous_normal = normal_level; previous_sustain = sustain_level;
        end
        if (normal_idle == 0 || sustain_idle < 3*normal_idle ||
            sustain_level != 0 || normal_level != 0)
            $fatal(1, "FAIL: pluck sustain damping length/idle");
        $display("PASS: optional pluck sustain keeps Attack and extends latched Release %0d to %0d samples",
                 normal_idle, sustain_idle);
        $finish;
    end
endmodule
