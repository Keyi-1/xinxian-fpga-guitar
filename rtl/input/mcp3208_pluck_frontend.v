`include "../config/guitar_config.vh"

// Audio-clock board front end from MCP3208 SPI data to four pluck events.
module mcp3208_pluck_frontend #(
    parameter integer SPI_CLK_DIV = `ADC_SPI_CLK_DIV,
    parameter integer DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter [11:0] BASELINE_CODE_CH0 = `ADC_BASELINE_CODE_CH0,
    parameter [11:0] BASELINE_CODE_CH1 = `ADC_BASELINE_CODE_CH1,
    parameter [11:0] BASELINE_CODE_CH2 = `ADC_BASELINE_CODE_CH2,
    parameter [11:0] BASELINE_CODE_CH3 = `ADC_BASELINE_CODE_CH3,
    parameter integer CAPTURE_SAMPLES = `VELOCITY_CAPTURE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,

    output wire [3:0]  pluck_valid,
    output wire [7:0]  velocity_level,
    output wire [47:0] raw_adc,
    output wire [47:0] peak_adc,
    output wire [31:0] event_timestamp,
    output wire [3:0] capture_pending
);

    wire        sample_valid;
    wire [1:0]  sample_string;
    wire [11:0] sample_data;

    mcp3208_four_channel_reader #(
        .CLK_DIV(SPI_CLK_DIV)
    ) u_mcp3208_four_channel_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .adc_cs_n     (adc_cs_n),
        .adc_sclk     (adc_sclk),
        .adc_mosi     (adc_mosi),
        .adc_miso     (adc_miso),
        .sample_valid (sample_valid),
        .sample_string(sample_string),
        .sample_data  (sample_data)
    );

    four_string_pluck_detector #(
        .DEAD_SAMPLES(DEAD_SAMPLES),
        .SETTLE_SAMPLES(SETTLE_SAMPLES), .CAPTURE_SAMPLES(CAPTURE_SAMPLES),
        .BASELINE_CODE_CH0(BASELINE_CODE_CH0),.BASELINE_CODE_CH1(BASELINE_CODE_CH1),
        .BASELINE_CODE_CH2(BASELINE_CODE_CH2),.BASELINE_CODE_CH3(BASELINE_CODE_CH3),
        .FIXED_VELOCITY_ENABLE(FIXED_VELOCITY_ENABLE)
    ) u_four_string_pluck_detector (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_valid   (sample_valid),
        .sample_string  (sample_string),
        .sample_data    (sample_data),
        .pluck_valid    (pluck_valid),
        .velocity_level (velocity_level),
        .raw_adc        (raw_adc),
        .peak_adc       (peak_adc),
        .event_timestamp(event_timestamp),.capture_pending(capture_pending)
    );

endmodule
