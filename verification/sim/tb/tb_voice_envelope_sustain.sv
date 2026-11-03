`timescale 1ns/1ps

module tb_voice_envelope_sustain;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg note_on;
    reg note_off;
    wire [15:0] normal_level;
    wire [15:0] sustained_level;
    wire normal_active;
    wire sustained_active;

    voice_envelope #(
        .ATTACK_SAMPLES(2), .DECAY_SAMPLES(2),
        .RELEASE_SAMPLES(8), .SUSTAIN_LEVEL(16384)
    ) u_normal (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(note_off), .velocity_level(2'd3),
        .sustain_enable(1'b0), .env_level(normal_level),
        .active(normal_active)
    );

    voice_envelope #(
        .ATTACK_SAMPLES(2), .DECAY_SAMPLES(2),
        .RELEASE_SAMPLES(8), .SUSTAIN_LEVEL(16384)
    ) u_sustained (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on), .note_off(note_off), .velocity_level(2'd3),
        .sustain_enable(1'b1), .env_level(sustained_level),
        .active(sustained_active)
    );

    always #5 clk = ~clk;

    task tick;
        input on_value;
        input off_value;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            note_on = on_value;
            note_off = off_value;
            @(negedge clk);
            sample_ce = 1'b0;
            note_on = 1'b0;
            note_off = 1'b0;
        end
    endtask

    integer normal_release_ticks;
    integer sustained_release_ticks;
    integer guard;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_ce = 1'b0;
        note_on = 1'b0;
        note_off = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        tick(1'b1, 1'b0);
        repeat (8) tick(1'b0, 1'b0);
        if (!normal_active || !sustained_active ||
            (normal_level !== sustained_level)) begin
            $display("FAIL: sustain changed envelope before note_off");
            $finish;
        end

        tick(1'b0, 1'b1);
        normal_release_ticks = 0;
        sustained_release_ticks = 0;
        guard = 0;
        while (sustained_active && (guard < 128)) begin
            tick(1'b0, 1'b0);
            guard = guard + 1;
            if (normal_active)
                normal_release_ticks = normal_release_ticks + 1;
            if (sustained_active)
                sustained_release_ticks = sustained_release_ticks + 1;
        end
        if (sustained_active || normal_active) begin
            $display("FAIL: release did not terminate normal=%b sustained=%b",
                     normal_active, sustained_active);
            $finish;
        end
        if (sustained_release_ticks < (normal_release_ticks * 3)) begin
            $display("FAIL: extended release too short normal=%0d sustained=%0d",
                     normal_release_ticks, sustained_release_ticks);
            $finish;
        end

        $display("PASS: KEY3 sustain extends Release normal=%0d extended=%0d",
                 normal_release_ticks, sustained_release_ticks);
        $finish;
    end

endmodule
