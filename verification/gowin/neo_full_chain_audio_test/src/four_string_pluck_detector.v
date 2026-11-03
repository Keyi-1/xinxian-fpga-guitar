`include "guitar_config.vh"

// 4 根弦独立触发检测：每根弦各自维护 armed/死区/连续落回判定，
// 互不影响。超过阈值就触发一次，不做力度分级（固定音量）。
module four_string_pluck_detector #(
    parameter [11:0]  TRIGGER_THRESHOLD = 12'd100,
    parameter [11:0]  REARM_THRESHOLD   = 12'd30,
    parameter [11:0]  BASELINE_CODE     = 12'd2053,
    parameter integer DEAD_SAMPLES      = 400,
    parameter integer SETTLE_SAMPLES    = 80
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [1:0]  sample_string,
    input  wire [11:0] sample_data,

    output reg  [3:0]  pluck_valid
);

    reg [3:0]  armed;
    reg [15:0] dead_count   [0:3];
    reg [7:0]  settle_count [0:3];
    integer i;

    wire [11:0] magnitude = (sample_data >= BASELINE_CODE)
                          ? (sample_data - BASELINE_CODE)
                          : (BASELINE_CODE - sample_data);

    always @(posedge clk) begin
        if (!rst_n) begin
            pluck_valid <= 4'd0;
            armed       <= 4'b1111;
            for (i = 0; i < 4; i = i + 1) begin
                dead_count[i]   <= 16'd0;
                settle_count[i] <= 8'd0;
            end
        end
        else begin
            pluck_valid <= 4'd0;

            if (sample_valid) begin
                // sample_string 指明这次读到的是哪根弦，只处理对应那一路的状态
                if (dead_count[sample_string] != 0)
                    dead_count[sample_string] <= dead_count[sample_string] - 1'b1;

                if (!armed[sample_string]) begin
                    if (magnitude <= REARM_THRESHOLD) begin
                        if (settle_count[sample_string] < SETTLE_SAMPLES)
                            settle_count[sample_string] <= settle_count[sample_string] + 1'b1;

                        if ((settle_count[sample_string] + 1 >= SETTLE_SAMPLES) &&
                            (dead_count[sample_string] == 0)) begin
                            armed[sample_string]        <= 1'b1;
                            settle_count[sample_string] <= 8'd0;
                        end
                    end
                    else begin
                        settle_count[sample_string] <= 8'd0;
                    end
                end
                else begin
                    if (magnitude >= TRIGGER_THRESHOLD) begin
                        pluck_valid[sample_string]  <= 1'b1;
                        armed[sample_string]        <= 1'b0;
                        dead_count[sample_string]   <= DEAD_SAMPLES;
                        settle_count[sample_string] <= 8'd0;
                    end
                end
            end
        end
    end

endmodule