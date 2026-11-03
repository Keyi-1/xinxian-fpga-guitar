`timescale 1ns/1ps

module tb_minimal_audio_core;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        voice_enable;
    reg [31:0] phase_inc;

    wire        sample_tick;
    wire        sample_valid;
    wire signed [23:0] pcm_out;

    reg [31:0] phase_inc_rom [0:35];

    integer valid_count;
    integer nonzero_count;
    integer mute_count;

    minimal_audio_core #(
        .SAMPLE_DIV(4)
    ) dut (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .voice_enable (voice_enable),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (sample_valid),
        .pcm_out      (pcm_out)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    initial begin
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        voice_enable  = 1'b0;
        phase_inc     = phase_inc_rom[0];

        valid_count   = 0;
        nonzero_count = 0;
        mute_count    = 0;

        repeat (3) @(posedge clk_audio_ref);
        rst_n        = 1'b1;
        voice_enable = 1'b1;

        while (valid_count < 10) begin
            @(posedge clk_audio_ref);
            #1;

            if (sample_valid) begin
                valid_count = valid_count + 1;

                if (pcm_out != 24'sd0)
                    nonzero_count = nonzero_count + 1;
            end
        end

        if (nonzero_count != 10) begin
            $display(
                "FAIL: voice enabled but PCM mostly zero, nonzero=%0d",
                nonzero_count
            );
            $finish;
        end

        voice_enable = 1'b0;

        while (mute_count < 4) begin
            @(posedge clk_audio_ref);
            #1;

            if (sample_valid) begin
                mute_count = mute_count + 1;

                if (pcm_out != 24'sd0) begin
                    $display(
                        "FAIL: voice disabled but PCM=%0d",
                        pcm_out
                    );
                    $finish;
                end
            end
        end

        $display(
            "PASS: minimal single-voice PCM chain, nonzero=%0d",
            nonzero_count
        );
        $finish;
    end

endmodule