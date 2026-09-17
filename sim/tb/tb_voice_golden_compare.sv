`timescale 1ns/1ps

module tb_voice_golden_compare;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        note_on;
    reg        note_off;
    reg [31:0] phase_inc;

    wire sample_tick;
    wire sample_valid;
    wire signed [23:0] pcm_out;
    wire [15:0] env_level;
    wire active;

    reg signed [23:0] golden_pcm24 [0:47];
    reg [31:0] phase_inc_rom [0:35];

    integer sample_index;
    integer mismatch_count;
    integer wait_cycles;

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

    // 等待 sample_tick 变为可见高电平，
    // 再保持事件到下一拍，让 envelope 在正确的采样沿消费事件
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

    task compare_next_sample;
    input integer index;
    begin
        wait_cycles = 0;

        // 等待当前 sample_valid 脉冲结束
        while (sample_valid === 1'b1) begin
            @(posedge clk_audio_ref);
            #1;
        end

        // 等待下一个新的 sample_valid 脉冲
        while (sample_valid !== 1'b1) begin
            @(posedge clk_audio_ref);
            #1;

            wait_cycles = wait_cycles + 1;

            if (wait_cycles > 20) begin
                $display(
                    "FAIL: timeout waiting sample index=%0d",
                    index
                );
                $finish;
            end
        end

        if (pcm_out !== golden_pcm24[index]) begin
            $display(
                "MISMATCH index=%0d rtl=%0d golden=%0d",
                index,
                pcm_out,
                golden_pcm24[index]
            );
            mismatch_count = mismatch_count + 1;
        end
    end
endtask

    initial begin
        $readmemh("../../sim/vectors/voice_e4_pcm24.mem", golden_pcm24);
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        note_on       = 1'b0;
        note_off      = 1'b0;
        phase_inc     = phase_inc_rom[0];

        sample_index   = 0;
        mismatch_count = 0;

        repeat (3) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        // 第 0 个音频采样触发 note_on
        apply_event_at_next_sample(1'b1, 1'b0);

        for (sample_index = 0;
             sample_index < 24;
             sample_index = sample_index + 1) begin
            compare_next_sample(sample_index);
        end

        // 第 24 个音频采样触发 note_off
        apply_event_at_next_sample(1'b0, 1'b1);

        for (sample_index = 24;
             sample_index < 48;
             sample_index = sample_index + 1) begin
            compare_next_sample(sample_index);
        end

        if (mismatch_count != 0) begin
            $display(
                "FAIL: golden comparison mismatches=%0d",
                mismatch_count
            );
            $finish;
        end

        $display(
            "PASS: RTL PCM matches Python golden vector, samples=48"
        );
        $finish;
    end

endmodule
