// 1024-point fixed-point radix-2 FFT for the post-effects PCM monitor.
// Input samples are captured in bit-reversed order with a Hann window.  One
// butterfly is reused for 5120 clocks; audio input is never backpressured.
module spectrum_fft1024 #(
    parameter integer FRAME_GAP_SAMPLES = 512
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid_in,
    input  wire signed [23:0] pcm_in,

    output reg                bin_valid,
    output reg [9:0]          bin_index,
    output reg [18:0]         bin_magnitude,
    output reg                frame_done,
    output reg                busy
);

    localparam [1:0] STATE_CAPTURE = 2'd0;
    localparam [1:0] STATE_FFT     = 2'd1;
    localparam [1:0] STATE_OUTPUT  = 2'd2;
    localparam [1:0] STATE_GAP     = 2'd3;

    reg [1:0] state;
    reg [9:0] capture_count;
    reg [9:0] output_count;
    reg [9:0] gap_count;
    reg [3:0] stage;
    reg [8:0] butterfly_count;

    reg signed [17:0] real_mem [0:1023];
    reg signed [17:0] imag_mem [0:1023];
    reg signed [15:0] hann_rom [0:1023];
    reg signed [15:0] cos_rom [0:511];
    reg signed [15:0] sin_rom [0:511];

    reg signed [15:0] pcm16;
    reg signed [31:0] window_product;
    reg signed [17:0] windowed_sample;

    integer half_size;
    integer group_number;
    integer butterfly_offset;
    integer index_a;
    integer index_b;
    integer twiddle_index;
    reg signed [17:0] a_re;
    reg signed [17:0] a_im;
    reg signed [17:0] b_re;
    reg signed [17:0] b_im;
    reg signed [15:0] tw_cos;
    reg signed [15:0] tw_sin;
    reg signed [34:0] product_re;
    reg signed [34:0] product_im;
    reg signed [18:0] twiddled_re;
    reg signed [18:0] twiddled_im;
    reg signed [19:0] sum_re;
    reg signed [19:0] sum_im;
    reg signed [19:0] diff_re;
    reg signed [19:0] diff_im;

    reg signed [17:0] output_re;
    reg signed [17:0] output_im;
    reg [18:0] abs_re;
    reg [18:0] abs_im;
    reg [18:0] magnitude_approx;

    function [9:0] reverse10;
        input [9:0] value;
        integer bit_index;
        begin
            for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1)
                reverse10[bit_index] = value[9-bit_index];
        end
    endfunction

    initial begin
        $readmemh("../../mem/hann1024_q15.mem", hann_rom);
        $readmemh("../../mem/fft1024_cos_q15.mem", cos_rom);
        $readmemh("../../mem/fft1024_sin_q15.mem", sin_rom);
    end

    always @* begin
        pcm16 = pcm_in[23:8];
        window_product = $signed(pcm16) * $signed(hann_rom[capture_count]);
        windowed_sample = window_product >>> 15;

        half_size = 1 << stage;
        group_number = butterfly_count >> stage;
        butterfly_offset = butterfly_count & (half_size - 1);
        index_a = (group_number << (stage + 1)) + butterfly_offset;
        index_b = index_a + half_size;
        twiddle_index = butterfly_offset << (9 - stage);

        a_re = real_mem[index_a];
        a_im = imag_mem[index_a];
        b_re = real_mem[index_b];
        b_im = imag_mem[index_b];
        tw_cos = cos_rom[twiddle_index];
        tw_sin = sin_rom[twiddle_index];
        product_re = $signed(b_re) * $signed(tw_cos) +
                     $signed(b_im) * $signed(tw_sin);
        product_im = $signed(b_im) * $signed(tw_cos) -
                     $signed(b_re) * $signed(tw_sin);
        twiddled_re = product_re >>> 15;
        twiddled_im = product_im >>> 15;
        sum_re = ($signed(a_re) + $signed(twiddled_re)) >>> 1;
        sum_im = ($signed(a_im) + $signed(twiddled_im)) >>> 1;
        diff_re = ($signed(a_re) - $signed(twiddled_re)) >>> 1;
        diff_im = ($signed(a_im) - $signed(twiddled_im)) >>> 1;

        output_re = real_mem[output_count];
        output_im = imag_mem[output_count];
        abs_re = output_re[17] ? -$signed(output_re) : output_re;
        abs_im = output_im[17] ? -$signed(output_im) : output_im;
        if (abs_re >= abs_im)
            magnitude_approx = abs_re + (abs_im >> 1);
        else
            magnitude_approx = abs_im + (abs_re >> 1);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_CAPTURE;
            capture_count <= 10'd0;
            output_count <= 10'd0;
            gap_count <= 10'd0;
            stage <= 4'd0;
            butterfly_count <= 9'd0;
            bin_valid <= 1'b0;
            bin_index <= 10'd0;
            bin_magnitude <= 19'd0;
            frame_done <= 1'b0;
            busy <= 1'b0;
        end
        else begin
            bin_valid <= 1'b0;
            frame_done <= 1'b0;
            case (state)
                STATE_CAPTURE: begin
                    busy <= 1'b0;
                    if (sample_valid_in) begin
                        real_mem[reverse10(capture_count)] <= windowed_sample;
                        imag_mem[reverse10(capture_count)] <= 18'sd0;
                        if (capture_count == 10'd1023) begin
                            capture_count <= 10'd0;
                            stage <= 4'd0;
                            butterfly_count <= 9'd0;
                            state <= STATE_FFT;
                            busy <= 1'b1;
                        end
                        else
                            capture_count <= capture_count + 1'b1;
                    end
                end

                STATE_FFT: begin
                    busy <= 1'b1;
                    real_mem[index_a] <= sum_re[17:0];
                    imag_mem[index_a] <= sum_im[17:0];
                    real_mem[index_b] <= diff_re[17:0];
                    imag_mem[index_b] <= diff_im[17:0];
                    if (butterfly_count == 9'd511) begin
                        butterfly_count <= 9'd0;
                        if (stage == 4'd9) begin
                            output_count <= 10'd0;
                            state <= STATE_OUTPUT;
                        end
                        else
                            stage <= stage + 1'b1;
                    end
                    else
                        butterfly_count <= butterfly_count + 1'b1;
                end

                STATE_OUTPUT: begin
                    busy <= 1'b1;
                    bin_valid <= 1'b1;
                    bin_index <= output_count;
                    bin_magnitude <= magnitude_approx;
                    if (output_count == 10'd511) begin
                        frame_done <= 1'b1;
                        gap_count <= 10'd0;
                        state <= STATE_GAP;
                        busy <= 1'b0;
                    end
                    else
                        output_count <= output_count + 1'b1;
                end

                default: begin
                    busy <= 1'b0;
                    if (sample_valid_in) begin
                        if (gap_count == FRAME_GAP_SAMPLES - 1) begin
                            gap_count <= 10'd0;
                            capture_count <= 10'd0;
                            state <= STATE_CAPTURE;
                        end
                        else
                            gap_count <= gap_count + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
