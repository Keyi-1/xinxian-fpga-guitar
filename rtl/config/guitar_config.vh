`ifndef XINXIAN_GUITAR_CONFIG_VH
`define XINXIAN_GUITAR_CONFIG_VH
`define AUDIO_SAMPLE_DIV 256

//包括矩阵扫描、去抖、滑音和再触发参数，后续需要调参
// Build modes
`define BUILD_MINIMAL 0
`define BUILD_FULL    1
`define BUILD_DEBUG   2

// Current default build
`define GUITAR_BUILD_MODE `BUILD_FULL
// Legacy physical-main tone when BOARD_USE_PIANO is disabled.
// FULL with LCD retains the optional 32-harmonic engine through USE_HARMONIC.
`define BOARD_USE_HARMONIC 0
// Experimental piano branch: eight measured modes and a short hammer ROM.
// Set to 0 to restore the preceding sine/anti-beat main path.
`define BOARD_USE_PIANO 1
`define BOARD_PIANO_HAMMER_ENABLE 1
`define BOARD_PIANO_ROOM_ENABLE 1
`define BOARD_ANTI_BEAT_ENABLE 1
// Use measured MCP3208 magnitude rather than a fixed level-2 velocity.
`define BOARD_FIXED_VELOCITY_ENABLE 0
`define BOARD_FIXED_VELOCITY 2'd2

// System clocks
`define SYSTEM_CLK_HZ     50000000
`define AUDIO_REF_CLK_HZ  12288000

// Audio
`define SAMPLE_RATE_HZ    48000
`define INTERNAL_PCM_BITS 24
`define DAC_BITS          16
`define VOICE_COUNT       4
`define HARMONICS_MAX     32
`define PHASE_ACC_BITS 32
// Exact current 36-note ROM increments fit in 26 bits (max 0x02CA6987).
// This bounds slide arithmetic only; DDS accumulators remain 32-bit.
`define NOTE_PHASE_VALUE_BITS 26
`define TIMBRE_BLEND_SAMPLES 256
`define FX_BLEND_SAMPLES 256
`define CHORUS_BASE_DELAY_SAMPLES 48
`define CHORUS_MOD_DEPTH_SAMPLES 16
`define CHORUS_LFO_HOLD_SAMPLES 512
`define REVERB_DELAY_A_SAMPLES 601
`define REVERB_DELAY_B_SAMPLES 947
`define REVERB_DELAY_C_SAMPLES 1423

// Left-hand matrix
`define FRET_STRINGS      4
`define FRET_COUNT        8
`define VELOCITY_LEVELS   4

// ADC
`define ADC_CHANNELS_USED 4
// ADC and matrix run in the 12.288 MHz audio domain, as on the verified board.
`define ADC_SPI_HZ        1536000
`define ADC_SPI_CLK_DIV   4
// Per-string calibration.  CH0..CH3 map to MCP3208 CH0..CH3 and to
// pluck_valid[0]..pluck_valid[3], respectively.  Start from a shared value;
// replace each group after collecting labelled UART measurements.
`define ADC_BASELINE_CODE_CH0 12'd2053
`define ADC_BASELINE_CODE_CH1 12'd2053
`define ADC_BASELINE_CODE_CH2 12'd2053
`define ADC_BASELINE_CODE_CH3 12'd2053
// rtl/config/guitar_config.vh

// CH0..CH3 trigger at the measured absolute deviations below (inclusive).
`define PLUCK_TRIGGER_THRESHOLD_CH0    12'd150
`define PLUCK_TRIGGER_THRESHOLD_CH1    12'd100
`define PLUCK_TRIGGER_THRESHOLD_CH2    12'd80
`define PLUCK_TRIGGER_THRESHOLD_CH3    12'd100

// All four channels must settle at deviation <=20 before rearming.
`define PLUCK_REARM_THRESHOLD_CH0      12'd20
`define PLUCK_REARM_THRESHOLD_CH1      12'd20
`define PLUCK_REARM_THRESHOLD_CH2      12'd20
`define PLUCK_REARM_THRESHOLD_CH3      12'd20

`define VELOCITY_LEVEL_1_THRESHOLD_CH0 12'd280
`define VELOCITY_LEVEL_2_THRESHOLD_CH0 12'd430
`define VELOCITY_LEVEL_3_THRESHOLD_CH0 12'd620

`define VELOCITY_LEVEL_1_THRESHOLD_CH1 12'd250
`define VELOCITY_LEVEL_2_THRESHOLD_CH1 12'd400
`define VELOCITY_LEVEL_3_THRESHOLD_CH1 12'd600

`define VELOCITY_LEVEL_1_THRESHOLD_CH2 12'd150
`define VELOCITY_LEVEL_2_THRESHOLD_CH2 12'd280
`define VELOCITY_LEVEL_3_THRESHOLD_CH2 12'd400

`define VELOCITY_LEVEL_1_THRESHOLD_CH3 12'd220
`define VELOCITY_LEVEL_2_THRESHOLD_CH3 12'd380
`define VELOCITY_LEVEL_3_THRESHOLD_CH3 12'd600

// Compatibility aliases for older modules that do not use per-string values.
`define ADC_BASELINE_CODE `ADC_BASELINE_CODE_CH0
`define PLUCK_TRIGGER_THRESHOLD `PLUCK_TRIGGER_THRESHOLD_CH0
`define PLUCK_REARM_THRESHOLD `PLUCK_REARM_THRESHOLD_CH0
`define VELOCITY_LEVEL_1_THRESHOLD `VELOCITY_LEVEL_1_THRESHOLD_CH0
`define VELOCITY_LEVEL_2_THRESHOLD `VELOCITY_LEVEL_2_THRESHOLD_CH0
`define VELOCITY_LEVEL_3_THRESHOLD `VELOCITY_LEVEL_3_THRESHOLD_CH0
`define VELOCITY_CAPTURE_SAMPLES   32
`define RETRIGGER_DEAD_SAMPLES 400
`define PLUCK_SETTLE_SAMPLES 80

// Display and FFT
`define FFT_SIZE          1024
`define SPECTRUM_BARS     32
`define DISPLAY_FPS       30

// Provisional control parameters
`define MATRIX_SCAN_HZ       1000
`define MATRIX_CLK_DIV       768
`define MATRIX_SETTLE_CYCLES 3
`define DEBOUNCE_SCANS       5
`define SLIDE_TIME_MS        20
`define SLIDE_SAMPLES        960
// Legacy metadata only; current board dead time counts ADC channel samples.
`define RETRIGGER_DEAD_MS    25

// Legacy optional same-fret tap gesture, outside the current board play path.
// Counted at the 48 kHz sample rate.
// Three valid re-presses at 5..16.7 Hz enter vibrato; a final release
// longer than 250 ms exits into the ordinary note release.
`define VIBRATO_TAP_COUNT           3
`define VIBRATO_MIN_TAP_SAMPLES     2880
`define VIBRATO_MAX_TAP_SAMPLES     9600
`define VIBRATO_EXIT_SAMPLES        12000
`define VIBRATO_WINDOW_SAMPLES      28800
`define VIBRATO_LFO_PHASE_INC       32'd536871
`define VIBRATO_DEPTH_Q15           16'd380

//正弦查找表配置
`define SINE_LUT_ADDR_BITS  10
`define SINE_LUT_SIZE       1024
`define SINE_LUT_VALUE_BITS 16

//增加包络设置：MINIMAL阶段初始参数
`define ENV_LEVEL_BITS       16
`define ENV_FULL_SCALE       32767
`define ENV_SUSTAIN_LEVEL    24576
`define ENV_ATTACK_SAMPLES   32
`define ENV_DECAY_SAMPLES    8192
`define ENV_RELEASE_SAMPLES  12288

//PT8211 DAC配置
`define PT8211_REF_DIV          4
`define PT8211_BITS_PER_FRAME   32

`endif
