module adc_uart #(
    parameter integer CLK_HZ = 12288000,
    parameter integer BAUD   = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        send,
    input  wire [11:0] adc_value,
    output reg         tx,
    output reg         busy
);

    localparam integer CLKS_PER_BIT = 107;

    // "ADC=" + 3位十六进制数 + CR + LF
    reg [7:0] message [0:8];

    reg [3:0]  char_index;
    reg [3:0]  bit_index;
    reg [31:0] clk_count;
    reg [7:0]  tx_byte;
    reg        sending;

    function [7:0] hex_ascii;
        input [3:0] value;
        begin
            if (value < 10)
                hex_ascii = "0" + value;
            else
                hex_ascii = "A" + (value - 10);
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            tx         <= 1'b1;
            busy       <= 1'b0;
            sending    <= 1'b0;
            char_index <= 4'd0;
            bit_index  <= 4'd0;
            clk_count  <= 32'd0;
            tx_byte    <= 8'd0;
        end
        else begin
            if (send && !busy) begin
                message[0] <= "A";
                message[1] <= "D";
                message[2] <= "C";
                message[3] <= "=";
                message[4] <= hex_ascii(adc_value[11:8]);
                message[5] <= hex_ascii(adc_value[7:4]);
                message[6] <= hex_ascii(adc_value[3:0]);
                message[7] <= 8'h0D; // 回车 CR
                message[8] <= 8'h0A; // 换行 LF

                char_index <= 4'd0;
                bit_index  <= 4'd0;
                clk_count  <= 32'd0;
                tx_byte    <= "A";

                tx      <= 1'b0; // 起始位
                busy    <= 1'b1;
                sending <= 1'b1;
            end
            else if (sending) begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 32'd0;

                    if (bit_index == 4'd9) begin
                        bit_index <= 4'd0;

                        if (char_index == 4'd8) begin
                            sending <= 1'b0;
                            busy    <= 1'b0;
                            tx      <= 1'b1;
                        end
                        else begin
                            char_index <= char_index + 1'b1;
                            tx_byte    <= message[char_index + 1'b1];
                            tx         <= 1'b0; // 下一个字符起始位
                        end
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;

                        if (bit_index == 4'd0)
                            tx <= tx_byte[0];       // 数据位 0
                        else if (bit_index < 4'd8)
                            tx <= tx_byte[bit_index];
                        else
                            tx <= 1'b1;             // 停止位
                    end
                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end
            end
        end
    end

endmodule