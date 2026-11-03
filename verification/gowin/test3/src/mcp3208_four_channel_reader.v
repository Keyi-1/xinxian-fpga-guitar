`include "guitar_config.vh"

module mcp3208_four_channel_reader #(
    parameter integer CLK_DIV = `ADC_SPI_CLK_DIV
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,

    output reg         sample_valid,
    output reg [1:0]   sample_string,
    output reg [11:0]  sample_data
);

    reg        start;
    reg        waiting_for_sample;
    reg [1:0]  current_string;
    wire       spi_busy;
    wire       spi_sample_valid;
    wire [2:0] spi_sample_channel;
    wire [11:0] spi_sample_data;

    mcp3208_spi #(
        .CLK_DIV(CLK_DIV)
    ) u_mcp3208_spi (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .channel       ({1'b0, current_string}),
        .busy          (spi_busy),
        .adc_cs_n      (adc_cs_n),
        .adc_sclk      (adc_sclk),
        .adc_mosi      (adc_mosi),
        .adc_miso      (adc_miso),
        .sample_valid  (spi_sample_valid),
        .sample_channel(spi_sample_channel),
        .sample_data   (spi_sample_data)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            start              <= 1'b0;
            waiting_for_sample <= 1'b0;
            current_string     <= 2'd0;
            sample_valid       <= 1'b0;
            sample_string      <= 2'd0;
            sample_data        <= 12'd0;
        end
        else begin
            start        <= 1'b0;
            sample_valid <= 1'b0;

            if (!waiting_for_sample && !spi_busy) begin
                start              <= 1'b1;
                waiting_for_sample <= 1'b1;
            end

            if (spi_sample_valid) begin
                sample_valid       <= 1'b1;
                sample_string      <= spi_sample_channel[1:0];
                // 补偿 mcp3208_spi.v 丢失的最低位 B0，和单通道版本一致
                sample_data        <= {spi_sample_data[10:0], 1'b1};
                current_string     <= current_string + 1'b1;
                waiting_for_sample <= 1'b0;
            end
        end
    end

endmodule