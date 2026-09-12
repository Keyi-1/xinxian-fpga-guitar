`timescale 1ns/1ps

module tb_minimal_top;

    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg rst_n;

    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;
    wire pa_en;
    wire led;

    integer capture_bit;
    integer frame_count;
    integer error_count;
    integer nonzero_frames;

    reg [15:0] captured_left;
    reg [15:0] captured_right;

    minimal_top #(
        .SAMPLE_DIV(4),
        .LED_HALF_PERIOD(20)
    ) dut (
        .sys_clk_50m     (sys_clk_50m),
        .audio_clk_12m288(audio_clk_12m288),
        .rst_n           (rst_n),
        .dac_bclk        (dac_bclk),
        .dac_lrck        (dac_lrck),
        .dac_din         (dac_din),
        .pa_en           (pa_en),
        .led             (led)
    );

    always #1 sys_clk_50m = ~sys_clk_50m;
    always #1 audio_clk_12m288 = ~audio_clk_12m288;

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
        sys_clk_50m      = 1'b0;
        audio_clk_12m288 = 1'b0;
        rst_n            = 1'b0;

        capture_bit    = 0;
        frame_count    = 0;
        error_count    = 0;
        nonzero_frames = 0;

        captured_left  = 16'h0000;
        captured_right = 16'h0000;

        repeat (5) @(posedge audio_clk_12m288);
        rst_n = 1'b1;

        wait (frame_count >= 6);
        #5;

        if (error_count != 0) begin
            $display(
                "FAIL: MINIMAL top protocol errors=%0d",
                error_count
            );
            $finish;
        end

        if (nonzero_frames == 0) begin
            $display("FAIL: fixed E4 tone produced no nonzero frame");
            $finish;
        end

        if (pa_en !== 1'b1) begin
            $display("FAIL: PA enable did not follow active voice");
            $finish;
        end

        $display(
            "PASS: fixed E4 dual-clock MINIMAL top, frames=%0d nonzero=%0d",
            frame_count,
            nonzero_frames
        );
        $finish;
    end

endmodule