`timescale 1ns/1ps

module tb_neo_minimal_audio_top;

    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg rst_n;

    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;
    wire pa_en_n;

    integer capture_bit;
    integer frame_count;
    integer nonzero_frames;
    integer error_count;
    integer pre_reset_nonzero;

    reg [15:0] captured_left;
    reg [15:0] captured_right;

    neo_minimal_audio_top dut (
        .sys_clk_50m      (sys_clk_50m),
        .audio_clk_12m288 (audio_clk_12m288),
        .rst_n            (rst_n),
        .dac_bclk         (dac_bclk),
        .dac_lrck         (dac_lrck),
        .dac_din          (dac_din),
        .pa_en_n          (pa_en_n)
    );

    // 仿真只要求两个时钟异步；缩短周期以加速回归。
    always #1.0 sys_clk_50m      = ~sys_clk_50m;
    always #1.3 audio_clk_12m288 = ~audio_clk_12m288;

    always @(posedge dac_bclk) begin
        if (dut.audio_rst_n) begin
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

                frame_count    = frame_count + 1;
                capture_bit    = 0;
                captured_left  = 16'h0000;
                captured_right = 16'h0000;
            end
            else begin
                capture_bit = capture_bit + 1;
            end
        end
    end

    task reset_capture_alignment;
        begin
            capture_bit    = 0;
            captured_left  = 16'h0000;
            captured_right = 16'h0000;
        end
    endtask

    initial begin
        sys_clk_50m      = 1'b0;
        audio_clk_12m288 = 1'b0;
        rst_n            = 1'b0;

        capture_bit       = 0;
        frame_count       = 0;
        nonzero_frames    = 0;
        error_count       = 0;
        pre_reset_nonzero = 0;
        captured_left     = 16'h0000;
        captured_right    = 16'h0000;

        repeat (6) @(posedge audio_clk_12m288);
        @(negedge audio_clk_12m288);
        rst_n = 1'b1;

        wait (dut.audio_rst_n === 1'b1);
        wait (nonzero_frames >= 4);

        if (pa_en_n !== 1'b0) begin
            $display("FAIL: MINIMAL PA was not enabled after first E4 trigger");
            $finish;
        end

        pre_reset_nonzero = nonzero_frames;

        // 运行中按下 KEY0：异步置位复位必须立即关闭功放。
        @(negedge audio_clk_12m288);
        rst_n = 1'b0;
        #0.1;

        if (dut.audio_rst_n !== 1'b0 || pa_en_n !== 1'b1) begin
            $display("FAIL: runtime reset did not mute PA asynchronously");
            $finish;
        end

        repeat (4) @(posedge audio_clk_12m288);
        #0.1;

        if (dac_bclk !== 1'b0 || dac_lrck !== 1'b0 || dac_din !== 1'b0) begin
            $display("FAIL: PT8211 outputs were not idle during runtime reset");
            $finish;
        end

        reset_capture_alignment();

        // 松开 KEY0：两拍同步释放后，固定 E4 必须重新触发。
        @(negedge audio_clk_12m288);
        rst_n = 1'b1;

        @(posedge audio_clk_12m288);
        #0.1;
        if (dut.audio_rst_n !== 1'b0 || pa_en_n !== 1'b1) begin
            $display("FAIL: audio reset released before synchronizer completed");
            $finish;
        end

        wait (dut.audio_rst_n === 1'b1);
        wait (nonzero_frames >= pre_reset_nonzero + 4);

        if (error_count != 0) begin
            $display("FAIL: MINIMAL runtime reset protocol errors=%0d", error_count);
            $finish;
        end

        if (pa_en_n !== 1'b0) begin
            $display("FAIL: MINIMAL PA did not re-enable after E4 retrigger");
            $finish;
        end

        $display(
            "PASS: MINIMAL runtime reset mutes and retriggers continuous E4"
        );
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: MINIMAL runtime reset test timed out");
        $finish;
    end

endmodule
