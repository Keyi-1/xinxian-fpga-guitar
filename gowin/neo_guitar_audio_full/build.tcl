set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
set repo_root [file normalize [file join $project_dir ../..]]
set rtl_files [list \
    [file join $repo_root rtl/top/neo_guitar_audio_full_top.v] \
    [file join $repo_root rtl/top/guitar_audio_top.v] \
    [file join $repo_root rtl/input/matrix_scanner.v] \
    [file join $repo_root rtl/input/mcp3208_spi.v] \
    [file join $repo_root rtl/input/mcp3208_four_channel_reader.v] \
    [file join $repo_root rtl/input/four_string_pluck_detector.v] \
    [file join $repo_root rtl/input/mcp3208_pluck_frontend.v] \
    [file join $repo_root rtl/control/guitar_effect_buttons.v] \
    [file join $repo_root rtl/control/debounced_toggle.v] \
    [file join $repo_root rtl/control/reset_sync.v] \
    [file join $repo_root rtl/control/guitar_play_control.v] \
    [file join $repo_root rtl/control/note_phase_table.v] \
    [file join $repo_root rtl/control/phase_slide_smoother.v] \
    [file join $repo_root rtl/control/voice_envelope.v] \
    [file join $repo_root rtl/control/timbre_blend_smoother.v] \
    [file join $repo_root rtl/synth/sine_nco.v] \
    [file join $repo_root rtl/synth/harmonic_voice_core.v] \
    [file join $repo_root rtl/synth/piano_voice_core.v] \
    [file join $repo_root rtl/synth/piano_hammer_model.v] \
    [file join $repo_root rtl/audio_io/four_string_board_audio_chain.v] \
    [file join $repo_root rtl/audio_io/four_voice_antibeat_allocator.v] \
    [file join $repo_root rtl/audio_io/stereo_audio_effects.v] \
    [file join $repo_root rtl/audio_io/four_voice_audio_core.v] \
    [file join $repo_root rtl/audio_io/four_voice_harmonic_audio_core.v] \
    [file join $repo_root rtl/audio_io/four_voice_piano_audio_core.v] \
    [file join $repo_root rtl/audio_io/piano_stereo_chorus.v] \
    [file join $repo_root rtl/audio_io/piano_stereo_effects.v] \
    [file join $repo_root rtl/audio_io/piano_stereo_room.v] \
    [file join $repo_root rtl/audio_io/voice_audio_core.v] \
    [file join $repo_root rtl/audio_io/sample_tick_gen.v] \
    [file join $repo_root rtl/audio_io/pcm24_mixer.v] \
    [file join $repo_root rtl/audio_io/pcm24_to_16.v] \
    [file join $repo_root rtl/audio_io/pcm24_rock_soft_clip.v] \
    [file join $repo_root rtl/audio_io/pcm24_chorus.v] \
    [file join $repo_root rtl/audio_io/pcm24_reverb.v] \
    [file join $repo_root rtl/audio_io/pt8211_tx.v] \
]
add_file -type verilog {*}$rtl_files
add_file -type cst [file join $repo_root constraints neo_guitar_audio_full.cst]
add_file -type sdc [file join $repo_root constraints neo_guitar_audio_full.sdc]
set_device GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module neo_guitar_audio_full_top
set_option -verilog_std v2001
set_option -include_path [file join $repo_root rtl config]
set_option -output_base_name neo_guitar_audio_full
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
run all
