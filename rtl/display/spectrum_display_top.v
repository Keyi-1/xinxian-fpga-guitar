// Complete post-effects spectrum path: 1024-point FFT, 32 log bars, coherent
// audio-to-pixel CDC and framebuffer-free RGB rendering.
module spectrum_display_top #(
    parameter integer FFT_FRAME_GAP_SAMPLES = 512,
    parameter integer H_ACTIVE = 800,
    parameter integer H_FRONT = 40,
    parameter integer H_SYNC = 128,
    parameter integer H_BACK = 88,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT = 13,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 31,
    parameter integer BAR_SLOT = 25,
    parameter integer BAR_WIDTH = 21
) (
    input  wire               audio_clk,
    input  wire               pixel_clk,
    input  wire               rst_n,
    input  wire               pcm_valid,
    input  wire signed [23:0] pcm_in,

    output wire               lcd_hsync,
    output wire               lcd_vsync,
    output wire               lcd_de,
    output wire [7:0]         lcd_r,
    output wire [7:0]         lcd_g,
    output wire [7:0]         lcd_b,
    output wire               spectrum_frame_update,
    output wire               display_frame_update,
    output wire               cdc_overrun
);

    wire bin_valid;
    wire [9:0] bin_index;
    wire [18:0] bin_magnitude;
    wire fft_frame_done;
    wire [4:0] bars_read_index;
    wire [8:0] bars_read_height;
    wire [8:0] peaks_read_height;
    wire [4:0] display_read_index;
    wire [8:0] display_bar_height;
    wire [8:0] display_peak_height;
    wire audio_rst_n;
    wire pixel_rst_n;

    reset_sync u_audio_reset_sync (
        .clk(audio_clk), .arst_n(rst_n), .srst_n(audio_rst_n)
    );

    reset_sync u_pixel_reset_sync (
        .clk(pixel_clk), .arst_n(rst_n), .srst_n(pixel_rst_n)
    );

    spectrum_fft1024 #(
        .FRAME_GAP_SAMPLES(FFT_FRAME_GAP_SAMPLES)
    ) u_spectrum_fft1024 (
        .clk(audio_clk), .rst_n(audio_rst_n), .sample_valid_in(pcm_valid),
        .pcm_in(pcm_in), .bin_valid(bin_valid), .bin_index(bin_index),
        .bin_magnitude(bin_magnitude), .frame_done(fft_frame_done), .busy()
    );

    spectrum_bars32 #(.DISPLAY_HEIGHT(V_ACTIVE)) u_spectrum_bars32 (
        .clk(audio_clk), .rst_n(audio_rst_n), .bin_valid(bin_valid),
        .bin_index(bin_index), .bin_magnitude(bin_magnitude),
        .frame_done(fft_frame_done), .read_index(bars_read_index),
        .bar_height_read(bars_read_height),
        .peak_height_read(peaks_read_height),
        .frame_update(spectrum_frame_update)
    );

    spectrum_bar_cdc u_spectrum_bar_cdc (
        .src_clk(audio_clk), .src_rst_n(audio_rst_n),
        .src_frame_update(spectrum_frame_update),
        .src_read_index(bars_read_index), .src_bar_height(bars_read_height),
        .src_peak_height(peaks_read_height), .src_overrun(cdc_overrun),
        .dst_clk(pixel_clk), .dst_rst_n(pixel_rst_n),
        .dst_read_index(display_read_index),
        .dst_bar_height(display_bar_height),
        .dst_peak_height(display_peak_height),
        .dst_frame_update(display_frame_update)
    );

    rgb_spectrum_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC),
        .H_BACK(H_BACK), .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC), .V_BACK(V_BACK), .BAR_SLOT(BAR_SLOT),
        .BAR_WIDTH(BAR_WIDTH)
    ) u_rgb_spectrum_timing (
        .pixel_clk(pixel_clk), .rst_n(pixel_rst_n),
        .bar_read_index(display_read_index),
        .bar_height(display_bar_height), .peak_height(display_peak_height),
        .lcd_hsync(lcd_hsync), .lcd_vsync(lcd_vsync), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .frame_start(), .pixel_x(), .pixel_y()
    );

endmodule
