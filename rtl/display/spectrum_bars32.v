// Reduces the 512 positive FFT bins to 32 approximately logarithmic bars.
// Each bar uses peak magnitude within the band; a separate peak marker falls
// by PEAK_DECAY pixels per spectrum frame.
module spectrum_bars32 #(
    parameter integer DISPLAY_HEIGHT = 400,
    parameter integer PEAK_DECAY = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bin_valid,
    input  wire [9:0]  bin_index,
    input  wire [18:0] bin_magnitude,
    input  wire        frame_done,
    input  wire [4:0]  read_index,

    output wire [8:0]  bar_height_read,
    output wire [8:0]  peak_height_read,
    output reg         frame_update
);

    reg [18:0] work_peak [0:31];
    reg [8:0] bar_height [0:31];
    reg [8:0] peak_height [0:31];
    reg [18:0] frame_candidate;
    integer i;

    assign bar_height_read = bar_height[read_index];
    assign peak_height_read = peak_height[read_index];

    function [4:0] map_bin_to_bar;
        input [9:0] fft_bin;
        begin
            if      (fft_bin <   2) map_bin_to_bar =  0;
            else if (fft_bin <   3) map_bin_to_bar =  1;
            else if (fft_bin <   4) map_bin_to_bar =  2;
            else if (fft_bin <   5) map_bin_to_bar =  3;
            else if (fft_bin <   6) map_bin_to_bar =  4;
            else if (fft_bin <   7) map_bin_to_bar =  5;
            else if (fft_bin <   8) map_bin_to_bar =  6;
            else if (fft_bin <   9) map_bin_to_bar =  7;
            else if (fft_bin <  10) map_bin_to_bar =  8;
            else if (fft_bin <  11) map_bin_to_bar =  9;
            else if (fft_bin <  12) map_bin_to_bar = 10;
            else if (fft_bin <  13) map_bin_to_bar = 11;
            else if (fft_bin <  14) map_bin_to_bar = 12;
            else if (fft_bin <  15) map_bin_to_bar = 13;
            else if (fft_bin <  19) map_bin_to_bar = 14;
            else if (fft_bin <  23) map_bin_to_bar = 15;
            else if (fft_bin <  27) map_bin_to_bar = 16;
            else if (fft_bin <  33) map_bin_to_bar = 17;
            else if (fft_bin <  41) map_bin_to_bar = 18;
            else if (fft_bin <  49) map_bin_to_bar = 19;
            else if (fft_bin <  60) map_bin_to_bar = 20;
            else if (fft_bin <  73) map_bin_to_bar = 21;
            else if (fft_bin <  89) map_bin_to_bar = 22;
            else if (fft_bin < 108) map_bin_to_bar = 23;
            else if (fft_bin < 131) map_bin_to_bar = 24;
            else if (fft_bin < 159) map_bin_to_bar = 25;
            else if (fft_bin < 193) map_bin_to_bar = 26;
            else if (fft_bin < 235) map_bin_to_bar = 27;
            else if (fft_bin < 285) map_bin_to_bar = 28;
            else if (fft_bin < 347) map_bin_to_bar = 29;
            else if (fft_bin < 421) map_bin_to_bar = 30;
            else                    map_bin_to_bar = 31;
        end
    endfunction

    function [8:0] magnitude_to_height;
        input [18:0] magnitude;
        reg [18:0] scaled;
        begin
            scaled = magnitude >> 4;
            if (scaled > DISPLAY_HEIGHT)
                magnitude_to_height = DISPLAY_HEIGHT;
            else
                magnitude_to_height = scaled[8:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_update <= 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                work_peak[i] <= 19'd0;
                bar_height[i] <= 9'd0;
                peak_height[i] <= 9'd0;
            end
        end
        else begin
            frame_update <= 1'b0;
            if (bin_valid && (bin_index != 0) &&
                (bin_magnitude > work_peak[map_bin_to_bar(bin_index)]))
                work_peak[map_bin_to_bar(bin_index)] <= bin_magnitude;

            if (frame_done) begin
                for (i = 0; i < 32; i = i + 1) begin
                    frame_candidate = work_peak[i];
                    if (bin_valid && (bin_index != 0) &&
                        (map_bin_to_bar(bin_index) == i) &&
                        (bin_magnitude > frame_candidate))
                        frame_candidate = bin_magnitude;
                    bar_height[i] <= magnitude_to_height(frame_candidate);
                    if (magnitude_to_height(frame_candidate) >= peak_height[i])
                        peak_height[i] <= magnitude_to_height(frame_candidate);
                    else if (peak_height[i] > PEAK_DECAY)
                        peak_height[i] <= peak_height[i] - PEAK_DECAY;
                    else
                        peak_height[i] <= 9'd0;
                    work_peak[i] <= 19'd0;
                end
                frame_update <= 1'b1;
            end
        end
    end

endmodule
