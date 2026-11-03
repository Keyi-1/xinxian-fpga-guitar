`timescale 1ns/1ps

module tb_voice_audio_core;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        note_on;
    reg        note_off;
    reg [31:0] phase_inc;

    wire        sample_tick;
    wire        sample_valid;
    wire signed [23:0] pcm_out;
    wire [15:0] env_level;
    wire        active;

    reg [31:0] phase_inc_rom [0:35];

    integer valid_count;
    integer nonzero_count;
    integer release_count;

    voice_audio_core #(
        .SAMPLE_DIV(4)
    ) dut (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .velocity_level(2'd3),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (sample_valid),
        .pcm_out      (pcm_out),
        .env_level    (env_level),
        .active       (active)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    initial begin
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        note_on       = 1'b0;
        note_off      = 1'b0;
        phase_inc     = phase_inc_rom[0];

        valid_count   = 0;
        nonzero_count = 0;
        release_count = 0;

        repeat (3) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        // 保持 note_on 足够长，确保被 sample_tick 采样
        note_on = 1'b1;
        repeat (6) begin
            @(posedge clk_audio_ref);
            #1;
        end
        note_on = 1'b0;

        while (valid_count < 12) begin
            @(posedge clk_audio_ref);
            #1;

            if (sample_valid) begin
                valid_count = valid_count + 1;

                if (pcm_out != 24'sd0)
                    nonzero_count = nonzero_count + 1;
            end
        end

        if (!active || nonzero_count < 8) begin
            $display(
                "FAIL: voice did not produce valid PCM, active=%b nonzero=%0d",
                active,
                nonzero_count
            );
            $finish;
        end

        // 触发 Release
        note_off = 1'b1;
        repeat (6) begin
            @(posedge clk_audio_ref);
            #1;
        end
        note_off = 1'b0;

        // Use the configured ADSR duration instead of the old 12-sample stub.
        while (active && release_count < 13000) begin
            @(posedge clk_audio_ref);
            #1;

            if (sample_valid)
                release_count = release_count + 1;
        end

        if (active || env_level != 0) begin
            $display(
                "FAIL: voice did not release, active=%b level=%0d",
                active,
                env_level
            );
            $finish;
        end

        $display(
            "PASS: NCO plus envelope PCM, nonzero=%0d",
            nonzero_count
        );
        $finish;
    end

endmodule
