`include "../config/guitar_config.vh"
module guitar_touch_game_audio #(
    parameter integer MATRIX_CLK_DIV=`MATRIX_CLK_DIV,
    parameter integer MATRIX_SETTLE_CYCLES=`MATRIX_SETTLE_CYCLES,
    parameter integer MATRIX_DEBOUNCE_FRAMES=`DEBOUNCE_SCANS,
    parameter integer ADC_SPI_CLK_DIV=`ADC_SPI_CLK_DIV,
    parameter integer PLUCK_DEAD_SAMPLES=`RETRIGGER_DEAD_SAMPLES,
    parameter integer PLUCK_SETTLE_SAMPLES=`PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE=`BOARD_FIXED_VELOCITY_ENABLE,
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1,ENABLE_MISS_CUE=1,USE_P2=0,WRITABLE=0
)(input wire clk,rst_n,command_valid,input wire [1:0] command_mode,
  output wire command_ack,input wire [7:0] fret_col_in_n,
  input wire [2:0] command_slot,input wire display_clk,display_read,input wire [10:0] display_address,
  output wire [95:0] display_data,output wire timbre_load,output wire [1:0] timbre_code,
  input wire [4:0] overlay_valid,input wire [479:0] overlay_data,
  input wire write_enable,input wire [10:0] write_address,input wire [95:0] write_data,
  output wire storage_idle,
  output wire [3:0] fret_row_oe,fret_row_drive_n,
  output wire adc_cs_n,adc_sclk,adc_mosi,input wire adc_miso,
  input wire timbre_select,rock_select,chorus_enable,sustain_enable,harmony_enable,reverb_enable,
  output wire dac_bclk,dac_lrck,dac_din,i2s_bclk,i2s_ws,i2s_data,
  output wire [399:0] visual_snapshot,output wire [255:0] game_snapshot,
  output wire final_pcm_valid,output wire signed [23:0] final_pcm,
  output wire posture_sample_tick,posture_performance,posture_pipeline_idle,posture_timbre_busy,
  output wire [3:0] posture_voice_active,posture_note_guard);
    reg [7:0] col_meta,col_sync;
    always @(posedge clk)begin
        if(!rst_n)begin col_meta<=255;col_sync<=255;end
        else begin col_meta<=fret_col_in_n;col_sync<=col_meta;end
    end
    wire stable_valid;
    wire [15:0] fret_id;
    wire [3:0] pluck_valid,active,note_on,note_off,force_release;
    wire [7:0] velocity,note_velocity;
    wire sample_tick,voice_valid;
    wire [1:0] mode;
    wire switching,miss_event;
    wire [127:0] target_phase,audible_phase;
    wire [95:0] voice_pcm;
    reg [3:0] note_activity;
    assign posture_sample_tick=sample_tick;
    assign posture_performance=mode==1 && !switching;
    assign posture_voice_active=active;
    assign posture_note_guard=note_activity | note_on | pluck_valid;
    always @(posedge clk)begin
        if(!rst_n)note_activity<=0;
        else if(sample_tick)note_activity<=note_on | pluck_valid;
        else note_activity<=note_activity | note_on | pluck_valid;
    end
    matrix_scanner #(.CLK_DIV(MATRIX_CLK_DIV),.SETTLE_CYCLES(MATRIX_SETTLE_CYCLES),
        .DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES)) u_matrix(
        .clk(clk),.rst_n(rst_n),.col_in_n(col_sync),.row_oe(fret_row_oe),.row_drive_n(fret_row_drive_n),
        .frame_valid(),.fret_mask(),.fret_id(),.stable_valid(stable_valid),.stable_fret_mask(),.stable_fret_id(fret_id));
    mcp3208_pluck_frontend #(.SPI_CLK_DIV(ADC_SPI_CLK_DIV),.DEAD_SAMPLES(PLUCK_DEAD_SAMPLES),
        .SETTLE_SAMPLES(PLUCK_SETTLE_SAMPLES),.FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE)) u_adc(
        .clk(clk),.rst_n(rst_n),.adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),.adc_mosi(adc_mosi),.adc_miso(adc_miso),
        .pluck_valid(pluck_valid),.velocity_level(velocity),.raw_adc(),.peak_adc(),.event_timestamp());
    generate if(USE_P2)begin:p2
    game_p2_mode_router #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW),.WRITABLE(WRITABLE)) u_router(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .command_slot(command_slot),.display_clk(display_clk),.display_read(display_read),
        .display_address(display_address),.display_data(display_data),.timbre_load(timbre_load),.timbre_code(timbre_code),
        .overlay_valid(overlay_valid),.overlay_data(overlay_data),.write_enable(write_enable),.write_address(write_address),.write_data(write_data),.storage_idle(storage_idle),
        .command_valid(command_valid),.command_mode(command_mode),.command_ack(command_ack),.mode(mode),.switching(switching),
        .stable_valid(stable_valid),.fret_id(fret_id),.pluck_valid(pluck_valid),.velocity(velocity),
        .voice_active(active),.audible_phase(audible_phase),.note_on(note_on),.note_off(note_off),
        .force_release(force_release),.target_phase(target_phase),.note_velocity(note_velocity),.game_snapshot(game_snapshot),
        .miss_event(miss_event));
    end else begin:p1
    audio_mode_router #(.ALLOW_AUTOPLAY_PREVIEW(ALLOW_AUTOPLAY_PREVIEW)) u_router(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .command_valid(command_valid),.command_mode(command_mode),.command_ack(command_ack),.mode(mode),.switching(switching),
        .stable_valid(stable_valid),.fret_id(fret_id),.pluck_valid(pluck_valid),.velocity(velocity),
        .voice_active(active),.audible_phase(audible_phase),.note_on(note_on),.note_off(note_off),
        .force_release(force_release),.target_phase(target_phase),.note_velocity(note_velocity),.game_snapshot(game_snapshot),
        .miss_event(miss_event));
    assign display_data=0;assign timbre_load=0;assign timbre_code=0;assign storage_idle=mode==0 && !switching;
    end endgenerate
    four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.GAME_CUE_ENABLE(ENABLE_MISS_CUE),.I2S_ENABLE(1),.USE_PIANO(1),
        .CONTROL_PHASE_VALUE_BITS(USE_P2 ? 27 : `NOTE_PHASE_VALUE_BITS),
        .PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) u_chain(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(1'b0),.stable_fret_id(16'd0),.pluck_valid(4'd0),
        .velocity_level(note_velocity),.timbre_select(timbre_select),.rock_select(rock_select),
        .chorus_enable(chorus_enable),.sustain_enable(sustain_enable),.harmony_enable(harmony_enable),.reverb_enable(reverb_enable),
        .sample_tick(sample_tick),.pcm_mix_valid(final_pcm_valid),.pcm_mix(final_pcm),.voice_active(active),.voice_pcm(voice_pcm),
        .display_phase_inc(audible_phase),.display_note_on(),.display_voice_sample_valid(voice_valid),
        .external_note_on(note_on),.external_note_off(note_off),.external_force_release(force_release),.external_phase_inc(target_phase),
        .game_cue_enable(mode==2 && !switching),.game_miss_event(miss_event),
        .control_pipeline_idle(posture_pipeline_idle),.control_timbre_busy(posture_timbre_busy),
        .dac_bclk(dac_bclk),.dac_lrck(dac_lrck),.dac_din(dac_din),.i2s_bclk(i2s_bclk),.i2s_ws(i2s_ws),.i2s_data(i2s_data));
    guitar_visual_telemetry #(.HOLD_INACTIVE_PITCH(1)) u_telemetry(.clk(clk),.rst_n(rst_n),
        .sample_tick(sample_tick),.voice_sample_valid(voice_valid),.phase_inc(audible_phase),
        .note_on(note_on),.voice_active(active),.fret_id(fret_id),.voice_pcm(voice_pcm),.snapshot(visual_snapshot));
endmodule
