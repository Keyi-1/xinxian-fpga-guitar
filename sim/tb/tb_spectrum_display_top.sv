`timescale 1ns/1ps

module tb_spectrum_display_top;
    reg audio_clk;
    reg pixel_clk;
    reg rst_n;
    reg pcm_valid;
    reg signed [23:0] pcm_in;
    wire lcd_hsync;
    wire lcd_vsync;
    wire lcd_de;
    wire [7:0] lcd_r;
    wire [7:0] lcd_g;
    wire [7:0] lcd_b;
    wire spectrum_frame_update;
    wire display_frame_update;
    wire cdc_overrun;
    integer n;
    integer colored_pixels;
    real angle;

    spectrum_display_top #(
        .FFT_FRAME_GAP_SAMPLES(8),
        .H_ACTIVE(64), .H_FRONT(2), .H_SYNC(4), .H_BACK(2),
        .V_ACTIVE(32), .V_FRONT(1), .V_SYNC(2), .V_BACK(1),
        .BAR_SLOT(2), .BAR_WIDTH(1)
    ) dut (
        .audio_clk(audio_clk), .pixel_clk(pixel_clk), .rst_n(rst_n),
        .pcm_valid(pcm_valid), .pcm_in(pcm_in),
        .lcd_hsync(lcd_hsync), .lcd_vsync(lcd_vsync), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .spectrum_frame_update(spectrum_frame_update),
        .display_frame_update(display_frame_update),
        .cdc_overrun(cdc_overrun)
    );

    always #5 audio_clk = ~audio_clk;
    always #7 pixel_clk = ~pixel_clk;
    always @(posedge pixel_clk) begin
        #1;
        if (lcd_de && ({lcd_r, lcd_g, lcd_b} != 24'd0))
            colored_pixels = colored_pixels + 1;
    end

    initial begin
        audio_clk = 1'b0;
        pixel_clk = 1'b0;
        rst_n = 1'b0;
        pcm_valid = 1'b0;
        pcm_in = 24'sd0;
        colored_pixels = 0;
        repeat (4) @(posedge audio_clk);
        #1 rst_n = 1'b1;
        // Allow the independent audio/pixel reset release pipelines to empty.
        repeat (4) @(posedge audio_clk);

        for (n = 0; n < 1024; n = n + 1) begin
            angle = 2.0 * 3.141592653589793 * 32.0 * n / 1024.0;
            @(negedge audio_clk);
            pcm_in = $rtoi($sin(angle) * 6000000.0);
            pcm_valid = 1'b1;
            @(negedge audio_clk);
            pcm_valid = 1'b0;
            repeat (2) @(negedge audio_clk);
        end

        wait (display_frame_update);
        #1;
        if (dut.u_spectrum_bar_cdc.display_bar[17] == 0) begin
            $display("FAIL: end-to-end spectrum did not populate tone bar 17");
            $finish;
        end
        repeat (3000) @(posedge pixel_clk);
        if (cdc_overrun || (colored_pixels == 0)) begin
            $display("FAIL: end-to-end display overrun=%b colored=%0d",
                     cdc_overrun, colored_pixels);
            $finish;
        end
        $display("PASS: PCM-to-1024FFT-to-32bars-to-RGB asynchronous display colored=%0d",
                 colored_pixels);
        $finish;
    end
endmodule
