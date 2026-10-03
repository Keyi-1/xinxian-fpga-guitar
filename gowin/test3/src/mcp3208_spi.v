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
    reg [4:0]  edge_count;      // 已完成的 SCLK 上升沿个数(0..18)
    reg [2:0]  channel_latched;
    reg [11:0] data_shift;
    reg [4:0]  cmd_shift;       // 命令移位寄存器: Start,SGL/DIFF,D2,D1,D0

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_count       <= 32'd0;
            edge_count      <= 5'd0;
            channel_latched <= 3'd0;
            data_shift      <= 12'd0;
            cmd_shift       <= 5'd0;
            busy            <= 1'b0;
            adc_cs_n        <= 1'b1;
            adc_sclk        <= 1'b0;
            adc_mosi        <= 1'b0;
            sample_valid    <= 1'b0;
            sample_channel  <= 3'd0;
            sample_data     <= 12'd0;
        end
        else begin
            sample_valid <= 1'b0;

            if (!busy) begin
                adc_cs_n  <= 1'b1;
                adc_sclk  <= 1'b0;
                clk_count <= 32'd0;

                if (start) begin
                    busy            <= 1'b1;
                    adc_cs_n        <= 1'b0;
                    adc_sclk        <= 1'b0;
                    channel_latched <= channel;
                    edge_count      <= 5'd0;
                    data_shift      <= 12'd0;
                    // Start=1, SGL/DIFF=1, D2, D1, D0
                    cmd_shift       <= {1'b1, 1'b1, channel[2], channel[1], channel[0]};
                    adc_mosi        <= 1'b1;   // Start 位先准备好，对应第1个上升沿
                end
            end
            else begin
                if (clk_count == CLK_DIV - 1) begin
                    clk_count <= 32'd0;

                    if (!adc_sclk) begin
                        // ---- 上升沿：ADC 读 MOSI，FPGA 读 MISO ----
                        adc_sclk <= 1'b1;

                        // 第7~18个上升沿(edge_count=6..17)是12位数据
                        if ((edge_count >= 5'd6) && (edge_count <= 5'd17))
                            data_shift <= {data_shift[10:0], adc_miso};

                        edge_count <= edge_count + 1'b1;
                    end
                    else begin
                        // ---- 下降沿：为下一个上升沿准备 MOSI ----
                        adc_sclk <= 1'b0;

                        // edge_count=1..4 时，还需要依次发 SGL/DIFF,D2,D1,D0
                        if ((edge_count >= 5'd1) && (edge_count <= 5'd4)) begin
                            adc_mosi  <= cmd_shift[3];
                            cmd_shift <= {cmd_shift[3:0], 1'b0};
                        end
                        else begin
                            adc_mosi <= 1'b0;
                        end

                        if (edge_count == 5'd18) begin
                            busy           <= 1'b0;
                            adc_cs_n       <= 1'b1;
                            adc_sclk       <= 1'b0;
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
    end

endmodule