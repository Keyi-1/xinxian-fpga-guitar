module guitar_radial_display(input wire audio_clk,audio_rst_n,clk,rst_n,
    input wire [399:0] audio_snapshot,input wire audio_pcm_valid,
    input wire signed [23:0] audio_pcm,
    output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
    output wire [5:0] lcd_r,lcd_g,lcd_b);
    wire [399:0] snapshot;
    wire update,frame_start,initialized,active,visual_update;
    wire [8:0] x,y;
    wire [11:0] mask;
    wire [3:0] display_active,display_flash,curve_active;
    wire renderer_deadline_miss;
    wire [43:0] hz;
    wire [15:0] fret,level;
    wire [31:0] strikes;
    wire [17:0] rgb;
    wire pcm_valid,pcm_overrun;
    wire signed [23:0] pcm;
    wire bin_valid,fft_done,fft_busy,bands_update;
    wire [9:0] bin_index;
    wire [18:0] bin_magnitude;
    wire [159:0] targets;
    guitar_visual_cdc u_cdc(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_snapshot(audio_snapshot),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_request(frame_start),.dst_snapshot(snapshot),.dst_update(update));
    guitar_pcm_cdc u_pcm(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_valid(audio_pcm_valid),
        .src_pcm(audio_pcm),.dst_clk(clk),.dst_rst_n(rst_n),.dst_valid(pcm_valid),.dst_pcm(pcm),.overrun(pcm_overrun));
    guitar_radial_fft u_fft(.clk(clk),.rst_n(rst_n),.sample_valid(pcm_valid),.pcm(pcm),
        .bin_valid(bin_valid),.bin_index(bin_index),.bin_magnitude(bin_magnitude),.frame_done(fft_done),.busy(fft_busy));
    guitar_radial_bands u_bands(.clk(clk),.rst_n(rst_n),.bin_valid(bin_valid),.bin_index(bin_index),
        .bin_magnitude(bin_magnitude),.frame_done(fft_done),.targets(targets),.update(bands_update));
    lcd_rgb_scan_480x272 u_scan(.clk(clk),.rst_n(rst_n && initialized),.pixel_rgb(rgb),
        .pixel_x(x),.pixel_y(y),.pixel_active(active),.frame_start(frame_start),
        .lcd_pclk(lcd_pclk),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),.lcd_de(lcd_de),
        .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    guitar_radial_curve_renderer u_renderer(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .snapshot(snapshot),.curve_active(curve_active),.pixel_x(x),.pixel_y(y),.pixel_active(active),.initialized(initialized),
        .mask(mask),.display_hz(hz),.display_fret(fret),.display_level(level),
        .display_active(display_active),.display_flash(display_flash),.deadline_miss(renderer_deadline_miss),
        .display_strikes(strikes),.visual_update(visual_update));
    guitar_radial_palette u_palette(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.visual_update(visual_update),
        .x(x),.y(y),.mask(mask),.hz(hz),.fret(fret),.level(level),.voice_active(display_active),
        .flash(display_flash),.strikes(strikes),.targets(targets),.rgb(rgb),.curve_active(curve_active));
    assign lcd_backlight=rst_n && initialized;
endmodule
