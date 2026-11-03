`include "guitar_config.vh"

module pt8211_tx #(
    parameter integer REF_DIV = `PT8211_REF_DIV
) (
    input  wire        clk_audio_ref,
    input  wire        rst_n,

    input  wire        sample_valid,
    input  wire [15:0] sample_left,
    input  wire [15:0] sample_right,

    output reg         dac_bclk,
    output reg         dac_lrck,
    output reg         dac_din
);

    reg [2:0]  ref_count;
    reg [4:0]  bit_count;
    reg [31:0] shift_reg;

    reg [15:0] current_left;
    reg [15:0] current_right;

    reg [15:0] pending_left;
    reg [15:0] pending_right;
    reg        pending_valid;

    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            ref_count     <= 3'd0;
            bit_count     <= 5'd0;
            shift_reg     <= 32'd0;

            current_left  <= 16'd0;
            current_right <= 16'd0;
            pending_left  <= 16'd0;
            pending_right <= 16'd0;
            pending_valid <= 1'b0;

            dac_bclk      <= 1'b0;
            dac_lrck      <= 1'b0;
            dac_din       <= 1'b0;
        end
        else begin
            // 暂存待发送的下一帧样本
            if (sample_valid) begin
                pending_left  <= sample_left;
                pending_right <= sample_right;
                pending_valid <= 1'b1;
            end

            if (ref_count == REF_DIV - 1) begin
                ref_count <= 3'd0;

                if (!dac_bclk) begin
                    // BCLK 上升沿：PT8211 采样数据
                    dac_bclk <= 1'b1;
                end
                else begin
                    // BCLK 下降沿：准备下一位数据
                    dac_bclk <= 1'b0;

                    if (bit_count == 5'd31) begin
                        // 一帧结束，装载下一帧
                        bit_count <= 5'd0;
                        dac_lrck  <= 1'b0;

                        if (sample_valid) begin
                            current_left  <= sample_left;
                            current_right <= sample_right;
                            pending_valid <= 1'b0;
                            shift_reg     <= {
                                sample_left,
                                sample_right
                            };
                            dac_din       <= sample_left[15];
                        end
                        else if (pending_valid) begin
                            current_left  <= pending_left;
                            current_right <= pending_right;
                            pending_valid <= 1'b0;
                            shift_reg     <= {
                                pending_left,
                                pending_right
                            };
                            dac_din       <= pending_left[15];
                        end
                        else begin
                            shift_reg <= {
                                current_left,
                                current_right
                            };
                            dac_din   <= current_left[15];
                        end
                    end
                    else begin
                        bit_count <= bit_count + 1'b1;

                        shift_reg <= {
                            shift_reg[30:0],
                            1'b0
                        };

                        dac_din <= shift_reg[30];

                        if (bit_count == 5'd15)
                            dac_lrck <= 1'b1;
                    end
                end
            end
            else begin
                ref_count <= ref_count + 1'b1;
            end
        end
    end

endmodule