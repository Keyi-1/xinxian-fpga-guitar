`include "../config/guitar_config.vh"

module pcm24_to_16 (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       pcm_valid,
    input  wire signed [23:0]          pcm_in,

    output reg                        sample_valid,
    output reg  signed [15:0]          sample_out
);

    reg signed [24:0] pcm_ext;
    reg signed [24:0] magnitude;
    reg signed [24:0] scaled_value;
    reg signed [15:0] converted_value;

    // 组合转换逻辑：24-bit → 16-bit
    always @* begin
        pcm_ext = {pcm_in[23], pcm_in};

        if (pcm_ext < 0) begin
            magnitude    = -pcm_ext;
            scaled_value = -((magnitude + 25'sd128) >>> 8);
        end
        else begin
            magnitude    = pcm_ext;
            scaled_value = (magnitude + 25'sd128) >>> 8;
        end

        if (scaled_value > 25'sd32767)
            converted_value = 16'sh7fff;
        else if (scaled_value < -25'sd32768)
            converted_value = 16'sh8000;
        else
            converted_value = scaled_value[15:0];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            sample_out   <= 16'sd0;
        end
        else begin
            sample_valid <= 1'b0;

            if (pcm_valid) begin
                sample_out   <= converted_value;
                sample_valid <= 1'b1;
            end
        end
    end

endmodule