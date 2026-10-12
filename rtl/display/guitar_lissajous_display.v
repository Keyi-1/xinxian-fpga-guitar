module guitar_lissajous_display(
    input wire audio_clk,audio_rst_n,clk,rst_n,
    input wire [399:0] audio_snapshot,
    output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
    output wire [5:0] lcd_r,lcd_g,lcd_b
);
    wire [399:0] snapshot;
    wire update,frame_start,initialized,active;
    wire [8:0] x,y;
    wire [11:0] mask;
    wire [3:0] display_active,display_flash;
    wire renderer_deadline_miss;
    wire [43:0] hz;
    wire [15:0] fret,level;
    wire [17:0] rgb;
    guitar_visual_cdc u_cdc(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_snapshot(audio_snapshot),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_request(frame_start),.dst_snapshot(snapshot),.dst_update(update));
    lcd_rgb_scan_480x272 u_scan(.clk(clk),.rst_n(rst_n && initialized),.pixel_rgb(rgb),
        .pixel_x(x),.pixel_y(y),.pixel_active(active),.frame_start(frame_start),
        .lcd_pclk(lcd_pclk),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),.lcd_de(lcd_de),
        .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    guitar_lissajous_renderer u_renderer(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .snapshot(snapshot),.pixel_x(x),.pixel_y(y),.pixel_active(active),.initialized(initialized),
        .mask(mask),.display_hz(hz),.display_fret(fret),.display_level(level),
        .display_active(display_active),.display_flash(display_flash),.deadline_miss(renderer_deadline_miss));
    guitar_lissajous_palette u_palette(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.x(x),.y(y),.mask(mask),
        .hz(hz),.fret(fret),.level(level),.voice_active(display_active),.flash(display_flash),.rgb(rgb));
    assign lcd_backlight=rst_n && initialized;
endmodule
