module guitar_touch_game_display #(parameter integer ALLOW_AUTOPLAY_PREVIEW=1,USE_P2=0)
    (input wire audio_clk,audio_rst_n,clk,rst_n,
    input wire [399:0] audio_snapshot,input wire [255:0] audio_game_snapshot,
    input wire audio_pcm_valid,input wire signed [23:0] audio_pcm,
    input wire [2:0] selected_slot,input wire [95:0] score_data,
    output wire score_read,output wire [10:0] score_address,output wire display_fault,
    input wire [2:0] page,input wire touch_ready,transition,
    output wire [255:0] ui_game_snapshot,
    output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
    output wire [5:0] lcd_r,lcd_g,lcd_b);
    wire [399:0] snapshot;
    wire update,frame_start,initialized,active,visual_update;
    wire [8:0] x,y;
    wire [11:0] mask;
    wire [3:0] display_active,display_flash,curve_active;
    wire [43:0] hz;
    wire [15:0] fret,level;
    wire [31:0] strikes;
    wire [17:0] radial_rgb,ui_rgb;
    wire [2:0] display_page;
    wire pcm_valid,pcm_overrun,bin_valid,fft_done,fft_busy,bands_update;
    wire signed [23:0] pcm;
    wire [9:0] bin_index;
    wire [18:0] bin_magnitude;
    wire [159:0] targets;
    wire renderer_deadline_miss,chart_update,chart_overflow,chart_deadline;
    wire [255:0] chart_snapshot;
    wire [383:0] centres;
    wire [287:0] tails;
    wire [31:0] valid_blocks;
    guitar_visual_cdc u_cdc(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_snapshot(audio_snapshot),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_request(frame_start),.dst_snapshot(snapshot),.dst_update(update));
    game_snapshot_cdc u_game_cdc(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_snapshot(audio_game_snapshot),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_request(frame_start),.dst_snapshot(ui_game_snapshot),.dst_update(chart_update));
    guitar_pcm_cdc u_pcm(.src_clk(audio_clk),.src_rst_n(audio_rst_n),.src_valid(audio_pcm_valid),
        .src_pcm(audio_pcm),.dst_clk(clk),.dst_rst_n(rst_n),.dst_valid(pcm_valid),.dst_pcm(pcm),.overrun(pcm_overrun));
    guitar_radial_fft u_fft(.clk(clk),.rst_n(rst_n),.sample_valid(pcm_valid),.pcm(pcm),
        .bin_valid(bin_valid),.bin_index(bin_index),.bin_magnitude(bin_magnitude),.frame_done(fft_done),.busy(fft_busy));
    guitar_radial_bands u_bands(.clk(clk),.rst_n(rst_n),.bin_valid(bin_valid),.bin_index(bin_index),
        .bin_magnitude(bin_magnitude),.frame_done(fft_done),.targets(targets),.update(bands_update));
    lcd_rgb_scan_480x272 u_scan(.clk(clk),.rst_n(rst_n && initialized),
        .pixel_rgb(display_page==1 && (touch_ready || y<252 || x<320) ? radial_rgb : ui_rgb),
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
        .flash(display_flash),.strikes(strikes),.targets(targets),.rgb(radial_rgb),.curve_active(curve_active));
    // The CDC destination holds one coherent word for the entire frame. Layout
    // and UI share this bank; only the next blank's request may replace it.
    generate if(USE_P2)begin:p2
    game_p2_chart_layout u_chart(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.snapshot_update(chart_update),
        .snapshot(ui_game_snapshot),.score_read(score_read),.score_address(score_address),.score_data(score_data),.centres(centres),.tails(tails),.valid_blocks(valid_blocks),
        .display_snapshot(chart_snapshot),.overflow(chart_overflow),.deadline_miss(chart_deadline));
    end else begin:p1
    game_chart_layout u_chart(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.snapshot_update(chart_update),
        .snapshot(ui_game_snapshot),.centres(centres),.tails(tails),.valid_blocks(valid_blocks),
        .display_snapshot(chart_snapshot),.overflow(chart_overflow),.deadline_miss(chart_deadline));
    assign score_read=0;assign score_address=0;
    end endgenerate
    assign display_fault=USE_P2 && (chart_overflow || chart_deadline);
    touch_game_renderer #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),.USE_P2(USE_P2)) u_ui(
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.page(page),
        .selected_slot(selected_slot),.display_fault(display_fault),.touch_ready(touch_ready),.transition(transition),.x(x),.y(y),.centres(centres),.tails(tails),
        .valid_blocks(valid_blocks),.game_snapshot(chart_snapshot),.rgb(ui_rgb),.display_page(display_page));
    assign lcd_backlight=rst_n && initialized;
endmodule
