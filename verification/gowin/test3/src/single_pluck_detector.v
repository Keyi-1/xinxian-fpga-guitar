`include "guitar_config.vh"

module single_pluck_detector #(
    parameter [11:0]  TRIGGER_THRESHOLD = 12'd400,
    parameter [11:0]  REARM_THRESHOLD   = 12'd120,
    parameter [11:0]  VELOCITY_1_THRESHOLD = 12'd500,
    parameter [11:0]  VELOCITY_2_THRESHOLD = 12'd800,
    parameter [11:0]  VELOCITY_3_THRESHOLD = 12'd1200,
    parameter integer DEAD_SAMPLES   = 2000,  // 原来 250 太短，拉长到约 150ms（按 ADC 采样率估算，烧录后可再调）
    parameter integer SETTLE_SAMPLES = 50,    // 必须连续这么多拍都低于 REARM 才算真正落回，不能一碰到就重新使能
    parameter [11:0]  BASELINE_CODE = 12'd2048
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [11:0] sample_data,

    output reg         pluck_valid,
    output reg  [1:0]  velocity_level,
    output reg  [11:0] peak_magnitude
);

    reg        armed;
    reg [15:0] dead_count;
    reg [7:0]  settle_count;

    wire [11:0] magnitude = (sample_data >= BASELINE_CODE)
                           ? (sample_data - BASELINE_CODE)
                           : (BASELINE_CODE - sample_data);

    function [1:0] velocity_from_sample;
        input [11:0] value;
        begin
            if (value >= VELOCITY_3_THRESHOLD)      velocity_from_sample = 2'd3;
            else if (value >= VELOCITY_2_THRESHOLD) velocity_from_sample = 2'd2;
            else if (value >= VELOCITY_1_THRESHOLD) velocity_from_sample = 2'd1;
            else                                    velocity_from_sample = 2'd0;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            pluck_valid    <= 1'b0;
            velocity_level <= 2'd0;
            peak_magnitude <= 12'd0;
            armed          <= 1'b1;
            dead_count     <= 16'd0;
            settle_count   <= 8'd0;
        end
        else begin
            pluck_valid <= 1'b0;

            if (sample_valid) begin
                if (dead_count != 0)
                    dead_count <= dead_count - 1'b1;

                if (!armed) begin
                    // 必须连续 SETTLE_SAMPLES 拍都落在 REARM 以内，才真正重新使能
                    // 中途只要有一拍超过 REARM，计数清零重新数——防止振铃尾巴把它骗重新使能
                    if (magnitude <= REARM_THRESHOLD) begin
                        if (settle_count < SETTLE_SAMPLES)
                            settle_count <= settle_count + 1'b1;
                        if ((settle_count + 1 >= SETTLE_SAMPLES) && (dead_count == 0)) begin
                            armed          <= 1'b1;
                            peak_magnitude <= magnitude;
                            settle_count   <= 8'd0;
                        end
                    end
                    else begin
                        settle_count <= 8'd0;
                    end
                end
                else begin
                    if (magnitude > peak_magnitude)
                        peak_magnitude <= magnitude;

                    if (magnitude >= TRIGGER_THRESHOLD) begin
                        pluck_valid    <= 1'b1;
                        velocity_level <= velocity_from_sample(magnitude);
                        armed          <= 1'b0;
                        dead_count     <= DEAD_SAMPLES;
                        settle_count   <= 8'd0;
                    end
                end
            end
        end
    end

endmodule