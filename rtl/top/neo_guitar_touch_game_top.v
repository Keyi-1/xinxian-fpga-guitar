`include "../config/guitar_config.vh"
// P2 keeps the accepted audio, effects and radial renderers. Touch
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
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1,ENABLE_MISS_CUE=1,USE_P2=1,WRITABLE=1,
    parameter integer UART_CLKS_PER_BIT=5208,ENABLE_IMU=1,IMU_I2C_QUARTER=125,
    parameter integer IMU_CALIBRATION_LOG2=8,IMU_HEALTH_MS=1000,IMU_STABLE_MS=500,IMU_COOLDOWN_MS=1000
)(input wire audio_clk_12m288,sys_clk_50m,
  input wire USER_BUTTON1_n,USER_BUTTON2_n,USER_BUTTON3_n,
  inout wire ROW0,ROW1,ROW2,ROW3,
  input wire COL0,COL1,COL2,COL3,COL4,COL5,COL6,COL7,
  output wire adc_cs_n,adc_sclk,adc_mosi,input wire adc_miso,
  output wire dac_bclk,dac_lrck,dac_din,pa_en_n,output wire [3:0] event_led,
  output wire lcd_pclk,lcd_hsync,lcd_vsync,lcd_de,lcd_backlight,
  output wire [5:0] lcd_r,lcd_g,lcd_b,
  output wire i2s_bclk,i2s_ws,i2s_data,
  inout wire ctp_scl,ctp_sda,ctp_int,output wire ctp_rst_n,
  input wire song_uart_rx,output wire song_uart_tx,
  inout wire imu_scl,imu_sda);
    reg [7:0] startup_count=0;
    always @(posedge audio_clk_12m288)if(startup_count!=255)startup_count<=startup_count+1'b1;
    wire startup_done=startup_count==255;
    wire audio_rst_n,lcd_rst_n;
    reset_sync u_startup(.clk(audio_clk_12m288),.arst_n(startup_done),.srst_n(audio_rst_n));
    reset_sync u_lcd_reset(.clk(sys_clk_50m),.arst_n(audio_rst_n),.srst_n(lcd_rst_n));
    wire timbre_select,rock_select,chorus_enable,sustain_enable,reverb_enable,harmony_enable;
    wire [1:0] timbre_mode,space_mode,timbre_code;
    wire timbre_load,display_read,display_fault;
    wire auto_timbre_load,manual_timbre_press;
    wire [1:0] auto_timbre_code;
    wire [10:0] display_address;wire [95:0] display_data;
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(KEY_LONG_PRESS_CYCLES),.EXTERNAL_TIMBRE_ENABLE(USE_P2 || ENABLE_IMU)) u_buttons(
        .load_timbre(timbre_load || auto_timbre_load),.loaded_timbre(timbre_load ? timbre_code : auto_timbre_code),
        .manual_timbre_press(manual_timbre_press),
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
    wire [2:0] page,selected_slot;
    wire [4:0] dst_command;
    wire [255:0] ui_game_snapshot,audio_game_snapshot;
    wire import_locked,storage_idle,frame_begin,score_write;
    wire verify_read;wire [10:0] verify_address;
    wire [10:0] score_write_address;wire [95:0] score_write_data;
    wire [4:0] system_catalog_valid,audio_catalog_valid;
    wire [479:0] system_catalog_data,audio_catalog_data;
    wire posture_sample_tick,posture_performance,posture_pipeline_idle,posture_timbre_busy;
    wire [3:0] posture_voice_active,posture_note_guard;
    wire [9:0] imu_status;
    generate if(ENABLE_IMU)begin:posture
        wire imu_ready,calibrated,calibrating,healthy,pose_event,tone_valid,math_deadline;
        wire [1:0] stable_pose,pose_tone;
        wire calibrate,auto_enable,arrived;
        wire [1:0] arrived_tone;
        wire pending;
        reg previous_auto,previous_performance;
        reg [1:0] healthy_sync,auto_sync,pending_sync;
        posture_touch_controls controls(.clk(sys_clk_50m),.rst_n(lcd_rst_n),.click(click),.double_click(double_click),
            .touch_ready(touch_ready),.page(page),.transition(transition),.import_locked(import_locked),
            .click_x(click_x),.click_y(click_y),.ready(imu_ready),.calibrated(calibrated),.calibrating(calibrating),
            .healthy(healthy),.calibrate(calibrate),.auto_enable(auto_enable));
        mpu6050_posture #(.I2C_QUARTER(IMU_I2C_QUARTER),.CALIBRATION_LOG2(IMU_CALIBRATION_LOG2),.HEALTH_MS(IMU_HEALTH_MS),
            .STABLE_MS(IMU_STABLE_MS),.COOLDOWN_MS(IMU_COOLDOWN_MS)) sensor(
            .clk(sys_clk_50m),.rst_n(lcd_rst_n),.tick_ms(tick_ms),.calibrate(calibrate),.scl(imu_scl),.sda(imu_sda),
            .ready(imu_ready),.calibrated(calibrated),.calibrating(calibrating),.healthy(healthy),
            .stable_pose(stable_pose),.pose_event(pose_event),.pose_timbre_valid(tone_valid),.pose_timbre(pose_tone),.deadline_miss(math_deadline));
        always @(posedge sys_clk_50m)begin
            if(!lcd_rst_n)begin previous_auto<=0;previous_performance<=0;pending_sync<=0;end
            else begin previous_auto<=auto_enable;previous_performance<=page==1;pending_sync<={pending_sync[0],pending};end
        end
        always @(posedge audio_clk_12m288)begin
            if(!audio_rst_n)begin healthy_sync<=0;auto_sync<=0;end
            else begin healthy_sync<={healthy_sync[0],healthy && !math_deadline};auto_sync<={auto_sync[0],auto_enable};end
        end
        posture_timbre_cdc transfer(.src_clk(sys_clk_50m),.src_rst_n(lcd_rst_n),
            .src_event((pose_event || (auto_enable && !previous_auto) || (page==1 && !previous_performance)) &&
                auto_enable && healthy && !math_deadline && page==1 && stable_pose!=0),
            .src_timbre(tone_valid ? pose_tone : 2'd3),.dst_clk(audio_clk_12m288),.dst_rst_n(audio_rst_n),
            .dst_event(arrived),.dst_timbre(arrived_tone));
        posture_timbre_policy policy(.clk(audio_clk_12m288),.rst_n(audio_rst_n),.sample_tick(posture_sample_tick),
            .auto_enable(auto_sync[1]),.sensor_healthy(healthy_sync[1]),.performance_mode(posture_performance),
            .mode_switching(dst_command_valid),.manual_press(manual_timbre_press),.explicit_timbre_load(timbre_load),
            .pose_event(arrived),.pose_timbre(arrived_tone),.current_timbre(timbre_mode),
            .voice_active(posture_voice_active),.pending_note_on(posture_note_guard),
            .pipeline_idle(posture_pipeline_idle),.timbre_busy(posture_timbre_busy),
            .load_timbre(auto_timbre_load),.loaded_timbre(auto_timbre_code),.pending(pending));
        assign imu_status={math_deadline,page!=1,pending_sync[1],stable_pose,auto_enable,healthy,calibrated,calibrating,imu_ready};
    end else begin:no_posture
        assign imu_scl=1'bz;assign imu_sda=1'bz;
        assign imu_status=0;assign auto_timbre_load=0;assign auto_timbre_code=0;
    end endgenerate
    generate if(USE_P2 && WRITABLE)begin:p3
    game_p3_service #(.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT)) service(
        .clk(sys_clk_50m),.rst_n(lcd_rst_n),.audio_clk(audio_clk_12m288),.audio_rst_n(audio_rst_n),
        .rx(song_uart_rx),.tx(song_uart_tx),.audio_idle(storage_idle),.frame_begin(frame_begin),
        .menu_idle((page==0 || page==2) && !transition && touch_ready && (import_locked || (!command_send && !click && !double_click))),
        .locked(import_locked),.write_enable(score_write),.write_address(score_write_address),.write_data(score_write_data),
        .verify_read(verify_read),.verify_address(verify_address),.verify_data(display_data),
        .system_valid(system_catalog_valid),.system_data(system_catalog_data),.audio_valid(audio_catalog_valid),.audio_data(audio_catalog_data));
    end else begin:no_import
    assign song_uart_tx=1;assign import_locked=0;assign score_write=0;assign score_write_address=0;assign score_write_data=0;
    assign verify_read=0;assign verify_address=0;
    assign system_catalog_valid=0;assign audio_catalog_valid=0;assign system_catalog_data=0;assign audio_catalog_data=0;
    end endgenerate
    touch_game_ui #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),.USE_P2(USE_P2),.WRITABLE(WRITABLE)) u_ui(
        .import_busy(import_locked),.overlay_valid(system_catalog_valid),
        .clk(sys_clk_50m),.rst_n(lcd_rst_n),.tick_ms(tick_ms),.touch_ready(touch_ready),
        .click(click),.double_click(double_click),.click_x(click_x),.click_y(click_y),.game_snapshot(ui_game_snapshot),
        .command_busy(command_busy),.command_done(command_done),.command_send(command_send),.command_mode(command_mode),
        .selected_slot(selected_slot),.display_fault(display_fault),.page(page),.flush_gesture(gesture_flush),.transition(transition));
    mode_command_cdc #(.WIDTH(5)) u_mode_cdc(.src_clk(sys_clk_50m),.src_rst_n(lcd_rst_n),.src_send(command_send),.src_mode({selected_slot,command_mode}),
        .src_busy(command_busy),.src_done(command_done),.dst_clk(audio_clk_12m288),.dst_rst_n(audio_rst_n),
        .dst_valid(dst_command_valid),.dst_mode(dst_command),.dst_ack(dst_command_ack));
    assign dst_command_mode=dst_command[1:0];
    wire [3:0] row_oe,row_drive_n;
    wire [399:0] visual_snapshot;
    wire final_pcm_valid;
    wire signed [23:0] final_pcm;
    // 声音和游戏控制主入口
    guitar_touch_game_audio #(.MATRIX_CLK_DIV(MATRIX_CLK_DIV),.MATRIX_SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .MATRIX_DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES),.ADC_SPI_CLK_DIV(ADC_SPI_CLK_DIV),
        .PLUCK_DEAD_SAMPLES(PLUCK_DEAD_SAMPLES),.PLUCK_SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES),
        .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE),.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),
        .ENABLE_MISS_CUE(ENABLE_MISS_CUE),.USE_P2(USE_P2),.WRITABLE(WRITABLE)) u_audio(
        .overlay_valid(audio_catalog_valid),.overlay_data(audio_catalog_data),.write_enable(score_write),.write_address(score_write_address),.write_data(score_write_data),.storage_idle(storage_idle),
        .clk(audio_clk_12m288),.rst_n(audio_rst_n),.command_valid(dst_command_valid),.command_mode(dst_command_mode),
        .command_slot(dst_command[4:2]),.display_clk(sys_clk_50m),.display_read(display_read || verify_read),
        .display_address(verify_read ? verify_address : display_address),.display_data(display_data),.timbre_load(timbre_load),.timbre_code(timbre_code),
        .command_ack(dst_command_ack),.fret_col_in_n({COL7,COL6,COL5,COL4,COL3,COL2,COL1,COL0}),
        .fret_row_oe(row_oe),.fret_row_drive_n(row_drive_n),.adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi),.adc_miso(adc_miso),.timbre_select(timbre_select),.rock_select(rock_select),
        .chorus_enable(chorus_enable),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),.reverb_enable(reverb_enable),
        .dac_bclk(dac_bclk),.dac_lrck(dac_lrck),.dac_din(dac_din),.i2s_bclk(i2s_bclk),.i2s_ws(i2s_ws),.i2s_data(i2s_data),
        .visual_snapshot(visual_snapshot),.game_snapshot(audio_game_snapshot),.final_pcm_valid(final_pcm_valid),.final_pcm(final_pcm),
        .posture_sample_tick(posture_sample_tick),.posture_performance(posture_performance),
        .posture_pipeline_idle(posture_pipeline_idle),.posture_timbre_busy(posture_timbre_busy),
        .posture_voice_active(posture_voice_active),.posture_note_guard(posture_note_guard));
    // 显示主入口
    guitar_touch_game_display #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),.USE_P2(USE_P2),.WRITABLE(WRITABLE),.IMU_ENABLE(ENABLE_IMU)) u_display(
        .imu_status(imu_status),
        .overlay_valid(system_catalog_valid),.overlay_data(system_catalog_data),.frame_begin(frame_begin),
        .audio_clk(audio_clk_12m288),.audio_rst_n(audio_rst_n),.clk(sys_clk_50m),.rst_n(lcd_rst_n),
        .audio_snapshot(visual_snapshot),.audio_game_snapshot(audio_game_snapshot),.audio_pcm_valid(final_pcm_valid),.audio_pcm(final_pcm),
        .selected_slot(selected_slot),.score_read(display_read),.score_address(display_address),.score_data(display_data),
        .display_fault(display_fault),.page(page),.touch_ready(touch_ready),.transition(transition || import_locked),.ui_game_snapshot(ui_game_snapshot),
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
