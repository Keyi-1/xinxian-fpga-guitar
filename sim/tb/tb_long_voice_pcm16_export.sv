`timescale 1ns/1ps

module tb_long_voice_pcm16_export;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        note_on;
    reg        note_off;
    reg [31:0] phase_inc;

    wire sample_tick;
    wire pcm24_valid;
    wire pcm16_valid;

    wire signed [23:0] pcm24;
    wire signed [15:0] pcm16;

    wire [15:0] env_level;
    wire active;

    reg [31:0] phase_inc_rom [0:35];

    integer export_file;
    integer sample_index;
    integer wait_cycles;

    voice_audio_core #(
        .SAMPLE_DIV(4)
    ) u_voice_audio_core (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .velocity_level(2'd3),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (pcm24_valid),
        .pcm_out      (pcm24),
        .env_level    (env_level),
        .active       (active)
    );

    pcm24_to_16 u_pcm24_to_16 (
        .clk         (clk_audio_ref),
        .rst_n       (rst_n),
        .pcm_valid   (pcm24_valid),
        .pcm_in      (pcm24),
        .sample_valid(pcm16_valid),
        .sample_out  (pcm16)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    task apply_event_at_next_sample;
        input event_note_on;
        input event_note_off;
        begin
            while (sample_tick !== 1'b1) begin
                @(posedge clk_audio_ref);
                #1;
            end

            note_on  = event_note_on;
            note_off = event_note_off;

            @(posedge clk_audio_ref);
            #1;

            note_on  = 1'b0;
            note_off = 1'b0;
        end
    endtask

    task export_next_sample;
        begin
            wait_cycles = 0;

            while (pcm16_valid === 1'b1) begin
                @(posedge clk_audio_ref);
                #1;
            end

            while (pcm16_valid !== 1'b1) begin
                @(posedge clk_audio_ref);
                #1;

                wait_cycles = wait_cycles + 1;

                if (wait_cycles > 24) begin
                    $display(
                        "FAIL: timeout at sample=%0d",
                        sample_index
                    );
                    $finish;
                end
            end

            $fwrite(export_file, "%04h\n", pcm16);
        end
    endtask

    initial begin
        $readmemh(
            "../../mem/note_phase_inc.mem",
            phase_inc_rom
        );

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        note_on       = 1'b0;
        note_off      = 1'b0;
        phase_inc     = phase_inc_rom[0];

        export_file = $fopen(
            "../vectors/rtl_e4_long_pcm16.mem",
            "w"
        );

        if (export_file == 0) begin
            $display("FAIL: cannot open long PCM export file");
            $finish;
        end

        repeat (3) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        // 第 0 个采样触发 note_on
        apply_event_at_next_sample(1'b1, 1'b0);

        // 输出到 note_off 前的样本
        for (sample_index = 0;
             sample_index < 36000;
             sample_index = sample_index + 1) begin
            export_next_sample;
        end

        // 第 36000 个采样触发 note_off
        apply_event_at_next_sample(1'b0, 1'b1);

        // 输出 Release 阶段样本
        for (sample_index = 36000;
             sample_index < 48800;
             sample_index = sample_index + 1) begin
            export_next_sample;
        end

        $fclose(export_file);

        $display(
            "PASS: exported long RTL PCM16 samples=48800"
        );
        $finish;
    end

endmodule
