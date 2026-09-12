`timescale 1ns/1ps

module tb_pcm16_golden_compare;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        note_on;
    reg        note_off;
    reg [31:0] phase_inc;

    wire signed [23:0] pcm24;
    wire                pcm24_valid;

    wire signed [15:0] pcm16;
    wire                pcm16_valid;

    wire sample_tick;
    wire [15:0] env_level;
    wire active;

    reg signed [15:0] golden_pcm16 [0:47];
    reg [31:0] phase_inc_rom [0:35];

    integer sample_index;
    integer mismatch_count;
    integer wait_cycles;
    integer export_file;

    voice_audio_core #(
        .SAMPLE_DIV(4)
    ) u_voice_audio_core (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
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

    task compare_next_sample;
        input integer index;
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
                        "FAIL: timeout waiting PCM16 index=%0d",
                        index
                    );
                    $finish;
                end
            end

            $fwrite(export_file, "%04h\n", pcm16);

            if (pcm16 !== golden_pcm16[index]) begin
                $display(
                    "MISMATCH index=%0d rtl=%0d golden=%0d",
                    index,
                    pcm16,
                    golden_pcm16[index]
                );
                mismatch_count = mismatch_count + 1;
            end
        end
    endtask

    initial begin
        $readmemh(
            "../../sim/vectors/voice_e4_pcm16.mem",
            golden_pcm16
        );

        $readmemh(
            "../../mem/note_phase_inc.mem",
            phase_inc_rom
        );

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        note_on       = 1'b0;
        note_off      = 1'b0;
        phase_inc     = phase_inc_rom[0];

        sample_index   = 0;
        mismatch_count = 0;

        export_file = $fopen(
            "../vectors/rtl_voice_e4_pcm16.mem",
            "w"
        );

        if (export_file == 0) begin
            $display("FAIL: cannot open RTL PCM export file");
            $finish;
        end

        repeat (3) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        apply_event_at_next_sample(1'b1, 1'b0);

        for (sample_index = 0;
             sample_index < 24;
             sample_index = sample_index + 1) begin
            compare_next_sample(sample_index);
        end

        apply_event_at_next_sample(1'b0, 1'b1);

        for (sample_index = 24;
             sample_index < 48;
             sample_index = sample_index + 1) begin
            compare_next_sample(sample_index);
        end

        $fclose(export_file);

        if (mismatch_count != 0) begin
            $display(
                "FAIL: PCM16 golden mismatches=%0d",
                mismatch_count
            );
            $finish;
        end

        $display(
            "PASS: RTL PCM16 matches Python golden vector, samples=48"
        );
        $finish;
    end

endmodule