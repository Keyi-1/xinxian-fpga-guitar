`timescale 1ns/1ps

module tb_voice_envelope;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg note_on;
    reg note_off;

    wire [15:0] env_level;
    wire        active;

    voice_envelope #(
        .ATTACK_SAMPLES (4),
        .DECAY_SAMPLES  (8),
        .RELEASE_SAMPLES(8),
        .SUSTAIN_LEVEL  (24576)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .sample_ce (sample_ce),
        .note_on   (note_on),
        .note_off  (note_off),
        .velocity_level(2'd3),
        .env_level (env_level),
        .active    (active)
    );

    always #5 clk = ~clk;

    task envelope_tick;
        input on_event;
        input off_event;
        begin
            sample_ce = 1'b1;
            note_on   = on_event;
            note_off  = off_event;

            @(posedge clk);
            #1;

            sample_ce = 1'b0;
            note_on   = 1'b0;
            note_off  = 1'b0;
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        sample_ce = 1'b0;
        note_on   = 1'b0;
        note_off  = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // note_on 后进入 Attack
        envelope_tick(1'b1, 1'b0);

        if (!active || env_level != 0) begin
            $display("FAIL: note_on initial state");
            $finish;
        end

        // Attack：4 个采样点后达到满幅
        repeat (4) envelope_tick(1'b0, 1'b0);

        if (env_level != 16'd32767) begin
            $display(
                "FAIL: attack level=%0d",
                env_level
            );
            $finish;
        end

        // Decay：8 个采样点后达到 Sustain
        repeat (8) envelope_tick(1'b0, 1'b0);

        if (env_level != 16'd24576) begin
            $display(
                "FAIL: sustain level=%0d",
                env_level
            );
            $finish;
        end

        // 进入 Release
        envelope_tick(1'b0, 1'b1);

        repeat (8) envelope_tick(1'b0, 1'b0);

        if (active || env_level != 0) begin
            $display(
                "FAIL: release state active=%b level=%0d",
                active,
                env_level
            );
            $finish;
        end

        $display("PASS: attack, decay, sustain and release envelope");
        $finish;
    end

endmodule
