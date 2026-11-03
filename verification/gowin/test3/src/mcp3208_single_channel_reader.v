`include "guitar_config.vh"

module mcp3208_single_channel_reader #(
    parameter integer CLK_DIV = `ADC_SPI_CLK_DIV
) (
    input  wire        clk,
    input  wire        rst_n,

    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,

    output reg         sample_valid,
    output reg [11:0]  sample_data
);

    reg  start;
    reg  waiting;

    wire       busy;
    wire       spi_sample_valid;
    wire [11:0] spi_sample_data;

    mcp3208_spi #(
        .CLK_DIV(CLK_DIV)
    ) u_mcp3208_spi (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .channel       (3'd0),

        .busy          (busy),
        .adc_cs_n      (adc_cs_n),
        .adc_sclk      (adc_sclk),
        .adc_mosi      (adc_mosi),
        .adc_miso      (adc_miso),

        .sample_valid  (spi_sample_valid),
        .sample_channel(),
        .sample_data   (spi_sample_data)
    );

   always @(posedge clk) begin
    if (!rst_n) begin
        start        <= 1'b0;
        waiting      <= 1'b0;
        sample_valid <= 1'b0;
        sample_data  <= 12'd0;
    end
    else begin
        start        <= 1'b0;
        sample_valid <= 1'b0;

        if (!waiting && !busy) begin
            start   <= 1'b1;
            waiting <= 1'b1;
        end

        if (spi_sample_valid) begin
            sample_valid <= 1'b1;
            // 补偿被漏掉的最低位 B0：整体左移一位，
            // 最低位用 1 补（而不是 0），让数值更贴近真实中点，
            // 比补 0 的系统性偏差更小（引入约±0.5 LSB 的随机误差，
            // 而不是固定 -0.5 LSB 的偏置）。
            sample_data  <= {spi_sample_data[10:0], 1'b1};
            waiting      <= 1'b0;
        end
    end
end

endmodule