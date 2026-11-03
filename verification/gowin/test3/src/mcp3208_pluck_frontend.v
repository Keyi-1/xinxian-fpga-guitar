`include "guitar_config.vh"

// System-clock front end from MCP3208 SPI data to four pluck events.
module mcp3208_pluck_frontend #(
    parameter integer SPI_CLK_DIV = `ADC_SPI_CLK_DIV,
    parameter integer DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter [11:0] BASELINE_CODE = 12'd0,
    parameter        USE_ABSOLUTE_DELTA = 1'b0,
    parameter [11:0] TRIGGER_THRESHOLD = `PLUCK_TRIGGER_THRESHOLD,
    parameter [11:0] REARM_THRESHOLD   = `PLUCK_REARM_THRESHOLD,
    parameter [11:0] VELOCITY_1_THRESHOLD = `VELOCITY_LEVEL_1_THRESHOLD,
    parameter [11:0] VELOCITY_2_THRESHOLD = `VELOCITY_LEVEL_2_THRESHOLD,
    parameter [11:0] VELOCITY_3_THRESHOLD = `VELOCITY_LEVEL_3_THRESHOLD
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
    output wire [31:0] event_timestamp
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
        .DEAD_SAMPLES         (DEAD_SAMPLES),
        .BASELINE_CODE        (BASELINE_CODE),
        .USE_ABSOLUTE_DELTA   (USE_ABSOLUTE_DELTA),
        .TRIGGER_THRESHOLD    (TRIGGER_THRESHOLD),
        .REARM_THRESHOLD      (REARM_THRESHOLD),
        .VELOCITY_1_THRESHOLD (VELOCITY_1_THRESHOLD),
        .VELOCITY_2_THRESHOLD (VELOCITY_2_THRESHOLD),
        .VELOCITY_3_THRESHOLD (VELOCITY_3_THRESHOLD)
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
        .event_timestamp(event_timestamp)
    );

endmodule
