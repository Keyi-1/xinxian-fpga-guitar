`ifndef XINXIAN_GUITAR_CONFIG_VH
`define XINXIAN_GUITAR_CONFIG_VH
`define AUDIO_SAMPLE_DIV 256

//包括矩阵扫描、去抖、滑音和再触发参数，后续需要调参
// Build modes
`define BUILD_MINIMAL 0
`define BUILD_FULL    1
`define BUILD_DEBUG   2

// Current default build
`define GUITAR_BUILD_MODE `BUILD_MINIMAL

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

// Left-hand matrix
`define FRET_STRINGS      4
`define FRET_COUNT        8
`define VELOCITY_LEVELS   4

// ADC
`define ADC_CHANNELS_USED 4
`define ADC_SPI_HZ        1000000

// Display and FFT
`define FFT_SIZE          1024
`define SPECTRUM_BARS     32
`define DISPLAY_FPS       30

// Provisional control parameters
`define MATRIX_SCAN_HZ       1000
`define DEBOUNCE_SCANS       3
`define SLIDE_TIME_MS        20
`define RETRIGGER_DEAD_MS    25

//正弦查找表配置
`define SINE_LUT_ADDR_BITS  10
`define SINE_LUT_SIZE       1024
`define SINE_LUT_VALUE_BITS 16

//增加包络设置：MINIMAL阶段初始参数
`define ENV_LEVEL_BITS       16
`define ENV_FULL_SCALE       32767
`define ENV_SUSTAIN_LEVEL    24576
`define ENV_ATTACK_SAMPLES   4
`define ENV_DECAY_SAMPLES    8
`define ENV_RELEASE_SAMPLES  8

`endif