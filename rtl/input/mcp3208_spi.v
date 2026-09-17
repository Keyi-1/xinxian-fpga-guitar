// Mode-0 single-ended MCP3208 conversion engine.
// A start request clocks: start, SGL/DIFF=1, channel[2:0], null, data[11:0].
module mcp3208_spi #(
    parameter integer CLK_DIV = 25
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [2:0]  channel,
    output reg         busy,

    output reg         adc_cs_n,
    output reg         adc_sclk,
    output reg         adc_mosi,
    input  wire        adc_miso,

    output reg         sample_valid,
    output reg [2:0]   sample_channel,
    output reg [11:0]  sample_data
);

    reg [31:0] clk_count;
    reg [4:0]  rising_count;
    reg [2:0]  channel_latched;
    reg [11:0] data_shift;

    function control_bit;
        input [2:0] index;
        input [2:0] selected_channel;
        begin
            case (index)
                3'd0: control_bit = 1'b1;
                3'd1: control_bit = 1'b1;
                3'd2: control_bit = selected_channel[2];
                3'd3: control_bit = selected_channel[1];
                default: control_bit = selected_channel[0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_count     <= 32'd0;
            rising_count  <= 5'd0;
            channel_latched <= 3'd0;
            data_shift    <= 12'd0;
            busy          <= 1'b0;
            adc_cs_n      <= 1'b1;
            adc_sclk      <= 1'b0;
            adc_mosi      <= 1'b0;
            sample_valid  <= 1'b0;
            sample_channel <= 3'd0;
            sample_data   <= 12'd0;
        end
        else begin
            sample_valid <= 1'b0;

            if (!busy) begin
                adc_cs_n <= 1'b1;
                adc_sclk <= 1'b0;
                clk_count <= 32'd0;

                if (start) begin
                    busy            <= 1'b1;
                    adc_cs_n        <= 1'b0;
                    adc_mosi        <= 1'b1;
                    rising_count    <= 5'd0;
                    channel_latched <= channel;
                    data_shift      <= 12'd0;
                end
            end
            else if (clk_count == CLK_DIV - 1) begin
                clk_count <= 32'd0;

                if (!adc_sclk) begin
                    // Rising edge: MCP3208 samples command and FPGA samples data.
                    adc_sclk <= 1'b1;
                    if ((rising_count >= 5'd6) && (rising_count <= 5'd17))
                        data_shift <= {data_shift[10:0], adc_miso};
                    rising_count <= rising_count + 1'b1;
                end
                else begin
                    // Falling edge: prepare the next command/data bit.
                    adc_sclk <= 1'b0;

                    if (rising_count < 5'd5)
                        adc_mosi <= control_bit(rising_count[2:0], channel_latched);
                    else
                        adc_mosi <= 1'b0;

                    if (rising_count == 5'd18) begin
                        busy           <= 1'b0;
                        adc_cs_n       <= 1'b1;
                        sample_valid   <= 1'b1;
                        sample_channel <= channel_latched;
                        sample_data    <= data_shift;
                    end
                end
            end
            else begin
                clk_count <= clk_count + 1'b1;
            end
        end
    end

endmodule
