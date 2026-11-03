`timescale 1ns/1ps

module tb_pt8211_tx;

    reg clk_audio_ref;
    reg rst_n;

    reg        sample_valid;
    reg [15:0] sample_left;
    reg [15:0] sample_right;

    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;

    integer capture_bit;
    integer frame_count;
    integer error_count;

    reg [15:0] expected_left;
    reg [15:0] expected_right;

    pt8211_tx dut (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .sample_left  (sample_left),
        .sample_right (sample_right),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    always @(posedge dac_bclk) begin
        if (capture_bit < 16) begin
            if (dac_lrck !== 1'b0)
                error_count = error_count + 1;

            if (dac_din !== expected_left[15-capture_bit])
                error_count = error_count + 1;
        end
        else begin
            if (dac_lrck !== 1'b1)
                error_count = error_count + 1;

            if (dac_din !==
                expected_right[15-(capture_bit-16)])
                error_count = error_count + 1;
        end

        if (capture_bit == 31) begin
            capture_bit = 0;
            frame_count = frame_count + 1;

            // 第一帧为复位后的零帧，第二帧开始检查测试数据
            if (frame_count == 1) begin
                expected_left  = 16'h1234;
                expected_right = 16'h5678;
            end
        end
        else begin
            capture_bit = capture_bit + 1;
        end
    end

    initial begin
        clk_audio_ref = 1'b0;
        rst_n         = 1'b0;

        sample_valid  = 1'b0;
        sample_left   = 16'h0000;
        sample_right  = 16'h0000;

        capture_bit   = 0;
        frame_count   = 0;
        error_count   = 0;

        expected_left  = 16'h0000;
        expected_right = 16'h0000;

        repeat (5) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        // 提交一帧测试数据
        sample_left  = 16'h1234;
        sample_right = 16'h5678;
        sample_valid = 1'b1;

        @(posedge clk_audio_ref);
        sample_valid = 1'b0;

        wait (frame_count >= 4);
        #5;

        if (error_count != 0) begin
            $display(
                "FAIL: PT8211 protocol errors=%0d",
                error_count
            );
            $finish;
        end

        $display(
            "PASS: PT8211 16-bit MSB-first LSB-justified frames=%0d",
            frame_count
        );
        $finish;
    end

endmodule