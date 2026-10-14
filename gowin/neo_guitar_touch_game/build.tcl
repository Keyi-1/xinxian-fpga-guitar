set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
set repo_root [file normalize [file join $project_dir ../..]]
foreach source {
    rtl/config/guitar_config.vh
    rtl/top/guitar_audio_top.v
    rtl/input/matrix_scanner.v
    rtl/input/mcp3208_spi.v
    rtl/input/mcp3208_four_channel_reader.v
    rtl/input/four_string_pluck_detector.v
    rtl/input/mcp3208_pluck_frontend.v
    rtl/control/guitar_effect_buttons.v
    rtl/control/debounced_toggle.v
    rtl/control/reset_sync.v
    rtl/control/guitar_play_control.v
    rtl/control/note_phase_table.v
    rtl/control/phase_slide_smoother.v
    rtl/control/voice_envelope.v
    rtl/control/timbre_blend_smoother.v
    rtl/synth/sine_nco.v
    rtl/synth/harmonic_voice_core.v
    rtl/synth/piano_voice_core.v
    rtl/synth/piano_hammer_model.v
    rtl/audio_io/four_voice_piano_audio_core.v
    rtl/audio_io/piano_stereo_chorus.v
    rtl/audio_io/piano_stereo_effects.v
    rtl/audio_io/piano_stereo_room.v
    rtl/audio_io/four_string_board_audio_chain.v
    rtl/audio_io/four_voice_antibeat_allocator.v
    rtl/audio_io/stereo_audio_effects.v
    rtl/audio_io/four_voice_audio_core.v
    rtl/audio_io/four_voice_harmonic_audio_core.v
    rtl/audio_io/voice_audio_core.v
    rtl/audio_io/sample_tick_gen.v
    rtl/audio_io/pcm24_mixer.v
    rtl/audio_io/pcm24_to_16.v
    rtl/audio_io/pcm24_rock_soft_clip.v
    rtl/audio_io/pcm24_chorus.v
    rtl/audio_io/pcm24_reverb.v
    rtl/audio_io/pt8211_tx.v
    rtl/audio_io/i2s_tx.v
    rtl/display/guitar_visual_telemetry.v
    rtl/display/guitar_visual_cdc.v
    rtl/display/guitar_scanline_ram.v
    rtl/display/guitar_lissajous_sine.v
    rtl/display/guitar_lissajous_arcsine.v
    rtl/display/guitar_lissajous_renderer.v
    rtl/display/guitar_lissajous_palette.v
    rtl/display/guitar_hz_bcd.v
    rtl/display/guitar_lissajous_display.v
    rtl/display/lcd_rgb_scan_480x272.v
    rtl/game/audio_mode_router.v
    rtl/game/game_chart_layout.v
    rtl/game/game_font_rom.v
    rtl/game/game_message_rom.v
    rtl/game/game_miss_audio_cue.v
    rtl/game/game_note_controller.v
    rtl/game/game_score_rom.v
    rtl/game/game_snapshot_cdc.v
    rtl/game/guitar_touch_game_audio.v
    rtl/game/guitar_touch_game_display.v
    rtl/game/mode_command_cdc.v
    rtl/game/touch_game_renderer.v
    rtl/game/touch_game_ui.v
    rtl/input/i2c_register_master.v
    rtl/input/gt911_touch.v
    rtl/input/touch_coordinate_mapper.v
    rtl/input/touch_gesture.v
    rtl/top/neo_guitar_touch_game_top.v
    rtl/display/guitar_pcm_cdc.v
    rtl/display/guitar_radial_display.v
    rtl/display/guitar_radial_fft.v
    rtl/display/guitar_radial_twiddle.v
    rtl/display/guitar_radial_bands.v
    rtl/display/guitar_radial_arcsine.v
    rtl/display/guitar_radial_curve_renderer.v
    rtl/display/guitar_radial_palette.v
    rtl/display/guitar_curve_envelope.v
    rtl/display/gowin_dpb_ram.v
} { add_file -type verilog [file join $repo_root $source] }
add_file -type cst [file join $repo_root constraints neo_guitar_touch_game.cst]
add_file -type sdc [file join $repo_root constraints neo_guitar_touch_game.sdc]
set_device -name GW5AT-60B GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module neo_guitar_touch_game_top
set_option -verilog_std v2001
set_option -include_path [file join $repo_root rtl config]
set_option -output_base_name neo_guitar_touch_game
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
set_option -place_option 4
set_option -route_option 2
set_option -clock_route_order 1
run all
