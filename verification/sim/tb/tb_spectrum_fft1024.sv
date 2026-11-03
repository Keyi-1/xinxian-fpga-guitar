`timescale 1ns/1ps

module tb_spectrum_fft1024;

    reg clk;
    reg rst_n;
    reg sample_valid_in;
    reg signed [23:0] pcm_in;
    wire bin_valid;
    wire [9:0] bin_index;
    wire [18:0] bin_magnitude;
    wire frame_done;
    wire busy;

    spectrum_fft1024 #(.FRAME_GAP_SAMPLES(8)) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid_in(sample_valid_in),
        .pcm_in(pcm_in), .bin_valid(bin_valid), .bin_index(bin_index),
        .bin_magnitude(bin_magnitude), .frame_done(frame_done), .busy(busy)
    );

    always #5 clk = ~clk;

    integer n;
    integer bin_count;
    integer peak_bin;
    integer peak_magnitude;
    real angle;

    always @(posedge clk) begin
        #1;
        if (bin_valid) begin
            bin_count = bin_count + 1;
            if (bin_magnitude > peak_magnitude) begin
                peak_magnitude = bin_magnitude;
                peak_bin = bin_index;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        pcm_in = 24'sd0;
        bin_count = 0;
        peak_bin = -1;
        peak_magnitude = 0;
        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        // Coherent bin-32 sine.  Samples are presented sparsely, as in the
        // real 48 kHz stream relative to the 12.288 MHz processing clock.
        for (n = 0; n < 1024; n = n + 1) begin
            angle = 2.0 * 3.141592653589793 * 32.0 * n / 1024.0;
            @(negedge clk);
            pcm_in = $rtoi($sin(angle) * 6000000.0);
            sample_valid_in = 1'b1;
            @(negedge clk);
            sample_valid_in = 1'b0;
            repeat (2) @(negedge clk);
        end

        wait (frame_done);
        #1;
        if (bin_count != 512) begin
            $display("FAIL: FFT bin count got=%0d expected=512", bin_count);
            $finish;
        end
        if ((peak_bin < 31) || (peak_bin > 33) || (peak_magnitude < 1000)) begin
            $display("FAIL: FFT peak bin=%0d magnitude=%0d expected near 32",
                     peak_bin, peak_magnitude);
            $finish;
        end

        $display("PASS: 1024-point Hann FFT coherent tone peak_bin=%0d magnitude=%0d bins=%0d",
                 peak_bin, peak_magnitude, bin_count);
        $finish;
    end

endmodule
