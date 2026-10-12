// Standalone 4.3-inch 480x272 demo. Keep NEO Dock J17 pins 1-2 jumpered.
module neo_lcd_lissajous_top #(
    parameter integer STARTUP_CYCLES=65536,
    parameter integer KEY_DEBOUNCE_CYCLES=1000000,
    parameter integer AUTO_MODE_FRAMES=512
) (
    input wire sys_clk,
    input wire sys_rst_n,
    input wire key_pattern_n,
    input wire key_pause_n,
    output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,
    output wire [5:0] lcd_r,lcd_g,lcd_b,
    output wire lcd_backlight
);
    reg [31:0] startup_count=0;
    reg startup_done=0;
    reg [1:0] reset_sync=2'b11;
    reg [1:0] mode_request=0;
    reg pause_request=0;
    wire run_n=startup_done && reset_sync[1];
    wire mode_press,pause_press,initialized,frame_start,pixel_active;
    wire [8:0] pixel_x,pixel_y;
    wire [3:0] intensity;
    wire [15:0] display_phase;
    wire [1:0] display_mode;
    wire display_paused;
    wire [17:0] pixel_rgb;
    always @(posedge sys_clk) begin
        reset_sync<={reset_sync[0],sys_rst_n};
        if(!startup_done) begin
            if(startup_count==STARTUP_CYCLES-1) startup_done<=1;
            else startup_count<=startup_count+1'b1;
        end
        if(!run_n) begin mode_request<=0; pause_request<=0; end
        else begin
            if(mode_press) mode_request<=mode_request+1'b1;
            if(pause_press) pause_request<=~pause_request;
        end
    end
    lcd_demo_button #(.STABLE_CYCLES(KEY_DEBOUNCE_CYCLES)) u_mode_key(
        .clk(sys_clk),.rst_n(run_n),.key_n(key_pattern_n),.press(mode_press));
    lcd_demo_button #(.STABLE_CYCLES(KEY_DEBOUNCE_CYCLES)) u_pause_key(
        .clk(sys_clk),.rst_n(run_n),.key_n(key_pause_n),.press(pause_press));
    lcd_rgb_scan_480x272 u_scan(.clk(sys_clk),.rst_n(run_n && initialized),
        .pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_active(pixel_active),.frame_start(frame_start),
        .lcd_pclk(lcd_pclk),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .lcd_de(lcd_de),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    lcd_lissajous_renderer #(.AUTO_MODE_FRAMES(AUTO_MODE_FRAMES)) u_renderer(
        .clk(sys_clk),.rst_n(run_n),.frame_start(frame_start),
        .mode_request(mode_request),.pause_request(pause_request),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_active(pixel_active),
        .initialized(initialized),.intensity(intensity),
        .display_phase(display_phase),.display_mode(display_mode),
        .display_paused(display_paused));
    lcd_neon_palette u_palette(.clk(sys_clk),.x(pixel_x),.y(pixel_y),.intensity(intensity),
        .animation_phase(display_phase),.mode(display_mode),
        .paused(display_paused),.rgb(pixel_rgb));
    // P20 controls LP3320 EN; resistor R48 still sets physical LED current.
    assign lcd_backlight=run_n && initialized;
endmodule

module lcd_demo_button #(parameter integer STABLE_CYCLES=1000000)(
    input wire clk,rst_n,key_n,output reg press
);
    reg [1:0] key_sync;
    reg stable_n;
    reg [31:0] count;
    always @(posedge clk) begin
        if(!rst_n) begin key_sync<=2'b11; stable_n<=1; count<=0; press<=0; end
        else begin
            key_sync<={key_sync[0],key_n}; press<=0;
            if(key_sync[1]==stable_n) count<=0;
            else if(count==STABLE_CYCLES-1) begin
                stable_n<=key_sync[1]; count<=0; press<=!key_sync[1];
            end else count<=count+1'b1;
        end
    end
endmodule
