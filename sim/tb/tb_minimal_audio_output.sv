`timescale 1ns/1ps

module tb_minimal_audio_output;

    reg        clk_audio_ref;
    reg        rst_n;
    reg        note_on;
    reg        note_off;
    reg [31:0] phase_inc;

    wire sample_tick;
    wire voice_active;
    wire pcm16_valid;

    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;

    reg [31:0] phase_inc_rom [0:35];

    integer capture_bit;
    integer frame_count;
    integer error_count;
    integer nonzero_frames;

    reg [15:0] captured_left;
    reg [15:0] captured_right;

    minimal_audio_output #(
        .SAMPLE_DIV(4)
    ) dut (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .voice_active (voice_active),
        .pcm16_valid  (pcm16_valid),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    always @(posedge dac_bclk) begin
        if (capture_bit < 16) begin
            if (dac_lrck !== 1'b0)
                error_count = error_count + 1;

            captured_left[15-capture_bit] = dac_din;
        end
        else begin
            if (dac_lrck !== 1'b1)
                error_count = error_count + 1;

            captured_right[15-(capture_bit-16)] = dac_din;
        end

        if (capture_bit == 31) begin
            if (captured_left !== captured_right)
                error_count = error_count + 1;

            if (captured_left !== 16'h0000 ||
                captured_right !== 16'h0000)
                nonzero_frames = nonzero_frames + 1;

            capture_bit = 0;
            frame_count = frame_count + 1;

            captured_left  = 16'h0000;
            captured_right = 16'h0000;
        end
        else begin
            capture_bit = capture_bit + 1;
        end
    end

    initial begin
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;
        note_on       = 1'b0;
        note_off      = 1'b0;
        phase_inc     = phase_inc_rom[0];

        capture_bit    = 0;
        frame_count    = 0;
        error_count    = 0;
        nonzero_frames = 0;

        captured_left  = 16'h0000;
        captured_right = 16'h0000;

        repeat (5) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        // 保持 note_on 足够长，确保被 48 kHz 采样节拍采到
        note_on = 1'b1;

        repeat (12) begin
            @(posedge clk_audio_ref);
            #1;
        end

        note_on = 1'b0;

        wait (frame_count >= 6);
        #5;

        if (error_count != 0) begin
            $display(
                "FAIL: PT8211 chain errors=%0d",
                error_count
            );
            $finish;
        end

        if (nonzero_frames == 0) begin
            $display("FAIL: no nonzero audio frame detected");
            $finish;
        end

        if (!voice_active) begin
            $display("FAIL: voice is not active");
            $finish;
        end

        $display(
            "PASS: MINIMAL audio chain, frames=%0d nonzero_frames=%0d",
            frame_count,
            nonzero_frames
        );
        $finish;
    end

endmodule