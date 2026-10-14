`include "../config/guitar_config.vh"
// Prototype keeps the accepted audio, effects and radial renderers. Touch
// RST/INT/SDA/SCL use the native six-pin J6 connector; see the project CST.
module neo_guitar_touch_game_top #(
    parameter integer KEY_DEBOUNCE_CYCLES=245760,
    parameter integer KEY_LONG_PRESS_CYCLES=12288000,
    parameter integer MATRIX_CLK_DIV=`MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES=`MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES=`DEBOUNCE_SCANS,
    parameter integer ADC_SPI_CLK_DIV=`ADC_SPI_CLK_DIV,
    parameter integer PLUCK_DEAD_SAMPLES=`RETRIGGER_DEAD_SAMPLES,
    parameter integer PLUCK_SETTLE_SAMPLES=`PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE=`BOARD_FIXED_VELOCITY_ENABLE,
    parameter integer TOUCH_SWAP_AXES=-1,TOUCH_MIRROR_X=0,TOUCH_MIRROR_Y=0,
    // Training defaults; set both to zero for a player-triggered-only build.
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1,ENABLE_MISS_CUE=1
)(input wire audio_clk_12m288,sys_clk_50m,
  input wire USER_BUTTON1_n,USER_BUTTON2_n,USER_BUTTON3_n,
  inout wire ROW0,ROW1,ROW2,ROW3,
  input wire COL0,COL1,COL2,COL3,COL4,COL5,COL6,COL7,
  output wire adc_cs_n,adc_sclk,adc_mosi,input wire adc_miso,
  output wire dac_bclk,dac_lrck,dac_din,pa_en_n,output wire [3:0] event_led,
  output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
  output wire [5:0] lcd_r,lcd_g,lcd_b,
  output wire i2s_bclk,i2s_ws,i2s_data,
  inout wire ctp_scl,ctp_sda,ctp_int,output wire ctp_rst_n);
    reg [7:0] startup_count=0;
    always @(posedge audio_clk_12m288)if(startup_count!=255)startup_count<=startup_count+1'b1;
    wire startup_done=startup_count==255;
    wire audio_rst_n,lcd_rst_n;
    reset_sync u_startup(.clk(audio_clk_12m288),.arst_n(startup_done),.srst_n(audio_rst_n));
    reset_sync u_lcd_reset(.clk(sys_clk_50m),.arst_n(audio_rst_n),.srst_n(lcd_rst_n));
    wire timbre_select,rock_select,chorus_enable,sustain_enable,reverb_enable,harmony_enable;
    wire [1:0] timbre_mode,space_mode;
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(KEY_LONG_PRESS_CYCLES)) u_buttons(
        .clk(audio_clk_12m288),.rst_n(audio_rst_n),.key_timbre_n(USER_BUTTON1_n),
        .key_chorus_n(USER_BUTTON2_n),.key_space_n(USER_BUTTON3_n),
        .timbre_select(timbre_select),.rock_select(rock_select),.timbre_mode(timbre_mode),
        .chorus_enable(chorus_enable),.sustain_enable(sustain_enable),.reverb_enable(reverb_enable),
        .space_mode(space_mode),.harmony_enable(harmony_enable));
    wire touch_ready,raw_valid,mapped_valid,click,double_click,gesture_flush;
    wire [3:0] raw_count,mapped_count;
    wire [7:0] raw_id,mapped_id,fault_count;
    wire [15:0] raw_x,raw_y,max_x,max_y;
    wire [8:0] touch_x,touch_y,click_x,click_y;
    wire [31:0] product_id;
    wire [15:0] firmware;
    gt911_touch u_touch(.clk(sys_clk_50m),.rst_n(lcd_rst_n),.ctp_scl(ctp_scl),.ctp_sda(ctp_sda),.ctp_int(ctp_int),
        .ctp_rst_n(ctp_rst_n),.ready(touch_ready),.frame_valid(raw_valid),.touch_count(raw_count),.touch_id(raw_id),
        .raw_x(raw_x),.raw_y(raw_y),.max_x(max_x),.max_y(max_y),.product_id(product_id),.firmware(firmware),
        .fault_count(fault_count),.selected_address());
    touch_coordinate_mapper #(.SWAP_AXES(TOUCH_SWAP_AXES),.MIRROR_X(TOUCH_MIRROR_X),.MIRROR_Y(TOUCH_MIRROR_Y)) u_coordinates(
        .clk(sys_clk_50m),.rst_n(lcd_rst_n),.frame_valid(raw_valid),.count(raw_count),.track_id(raw_id),
        .raw_x(raw_x),.raw_y(raw_y),.max_x(max_x),.max_y(max_y),
        .valid(mapped_valid),.mapped_count(mapped_count),.mapped_id(mapped_id),.x(touch_x),.y(touch_y));
    reg [15:0] millisecond_count;
    wire tick_ms=millisecond_count==49999;
    always @(posedge sys_clk_50m)begin
        if(!lcd_rst_n || tick_ms)millisecond_count<=0;
        else millisecond_count<=millisecond_count+1'b1;
    end
    touch_gesture u_gesture(.clk(sys_clk_50m),.rst_n(lcd_rst_n),.tick_ms(tick_ms),.flush(gesture_flush),
        .frame_valid(mapped_valid),.count(mapped_count),.track_id(mapped_id),.x(touch_x),.y(touch_y),
        .click(click),.double_click(double_click),.click_x(click_x),.click_y(click_y));
    wire command_send,command_busy,command_done,dst_command_valid,dst_command_ack,transition;
    wire [1:0] command_mode,dst_command_mode;
    wire [2:0] page;
    wire [255:0] ui_game_snapshot,audio_game_snapshot;
    touch_game_ui #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW)) u_ui(
        .clk(sys_clk_50m),.rst_n(lcd_rst_n),.tick_ms(tick_ms),.touch_ready(touch_ready),
        .click(click),.double_click(double_click),.click_x(click_x),.click_y(click_y),.game_snapshot(ui_game_snapshot),
        .command_busy(command_busy),.command_done(command_done),.command_send(command_send),.command_mode(command_mode),
        .page(page),.flush_gesture(gesture_flush),.transition(transition));
    mode_command_cdc u_mode_cdc(.src_clk(sys_clk_50m),.src_rst_n(lcd_rst_n),.src_send(command_send),.src_mode(command_mode),
        .src_busy(command_busy),.src_done(command_done),.dst_clk(audio_clk_12m288),.dst_rst_n(audio_rst_n),
        .dst_valid(dst_command_valid),.dst_mode(dst_command_mode),.dst_ack(dst_command_ack));
    wire [3:0] row_oe,row_drive_n;
    wire [399:0] visual_snapshot;
    wire final_pcm_valid;
    wire signed [23:0] final_pcm;
    guitar_touch_game_audio #(.MATRIX_CLK_DIV(MATRIX_CLK_DIV),.MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),.ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),
        .PLUCK_DEAD_SAMPLES(PLUCK_DEAD_SAMPLES),.PLUCK_SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES),
        .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE),.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),
        .ENABLE_MISS_CUE(ENABLE_MISS_CUE)) u_audio(
        .clk(audio_clk_12m288),.rst_n(audio_rst_n),.command_valid(dst_command_valid),.command_mode(dst_command_mode),
        .command_ack(dst_command_ack),.fret_col_in_n({COL7,COL6,COL5,COL4,COL3,COL2,COL1,COL0}),
        .fret_row_oe(row_oe),.fret_row_drive_n(row_drive_n),.adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi),.adc_miso(adc_miso),.timbre_select(timbre_select),.rock_select(rock_select),
        .chorus_enable(chorus_enable),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),.reverb_enable(reverb_enable),
        .dac_bclk(dac_bclk),.dac_lrck(dac_lrck),.dac_din(dac_din),.i2s_bclk(i2s_bclk),.i2s_ws(i2s_ws),.i2s_data(i2s_data),
        .visual_snapshot(visual_snapshot),.game_snapshot(audio_game_snapshot),.final_pcm_valid(final_pcm_valid),.final_pcm(final_pcm));
    guitar_touch_game_display #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW)) u_display(
        .audio_clk(audio_clk_12m288),.audio_rst_n(audio_rst_n),.clk(sys_clk_50m),.rst_n(lcd_rst_n),
        .audio_snapshot(visual_snapshot),.audio_game_snapshot(audio_game_snapshot),.audio_pcm_valid(final_pcm_valid),.audio_pcm(final_pcm),
        .page(page),.touch_ready(touch_ready),.transition(transition),.ui_game_snapshot(ui_game_snapshot),
        .lcd_pclk(lcd_pclk),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),.lcd_de(lcd_de),.lcd_backlight(lcd_backlight),
        .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    assign ROW0=row_oe[0]?row_drive_n[0]:1'bz;assign ROW1=row_oe[1]?row_drive_n[1]:1'bz;
    assign ROW2=row_oe[2]?row_drive_n[2]:1'bz;assign ROW3=row_oe[3]?row_drive_n[3]:1'bz;
    assign pa_en_n=~audio_rst_n;
    reg [21:0] rock_led_count;
    reg rock_led_on;
    always @(posedge audio_clk_12m288)begin
        if(!audio_rst_n || !rock_select)begin rock_led_count<=0;rock_led_on<=1;end
        else if(rock_led_count==3071999)begin rock_led_count<=0;rock_led_on<=~rock_led_on;end
        else rock_led_count<=rock_led_count+1'b1;
    end
    assign event_led=~{reverb_enable||(harmony_enable&&space_mode==0),sustain_enable||(harmony_enable&&space_mode==0),
                      chorus_enable,timbre_select||(rock_select&&rock_led_on)};
endmodule
