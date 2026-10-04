`include "../config/guitar_config.vh"

// Board-validated per-string trigger/rearm policy, extended with diagnostics
// and an explicitly optional magnitude-based four-level velocity mapping.
module four_string_pluck_detector #(
    parameter [11:0] TRIGGER_THRESHOLD = `PLUCK_TRIGGER_THRESHOLD,
    parameter [11:0] REARM_THRESHOLD = `PLUCK_REARM_THRESHOLD,
    parameter [11:0] BASELINE_CODE = `ADC_BASELINE_CODE,
    parameter USE_ABSOLUTE_DELTA = 1'b1,
    parameter integer DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE,
    parameter [1:0] FIXED_VELOCITY = `BOARD_FIXED_VELOCITY,
    parameter [11:0] VELOCITY_1_THRESHOLD = `VELOCITY_LEVEL_1_THRESHOLD,
    parameter [11:0] VELOCITY_2_THRESHOLD = `VELOCITY_LEVEL_2_THRESHOLD,
    parameter [11:0] VELOCITY_3_THRESHOLD = `VELOCITY_LEVEL_3_THRESHOLD
) (
    input wire clk, rst_n, sample_valid,
    input wire [1:0] sample_string,
    input wire [11:0] sample_data,
    output reg [3:0] pluck_valid,
    output reg [7:0] velocity_level,
    output reg [47:0] raw_adc, peak_adc,
    output reg [31:0] event_timestamp
);
    reg [3:0] armed;
    reg [15:0] dead_count [0:3];
    reg [15:0] settle_count [0:3];
    reg [31:0] timestamp_count;
    wire [11:0] magnitude = !USE_ABSOLUTE_DELTA ? sample_data :
        (sample_data >= BASELINE_CODE ? sample_data - BASELINE_CODE :
                                       BASELINE_CODE - sample_data);
    function [1:0] velocity_from_sample;
        input [11:0] value;
        begin
            if (FIXED_VELOCITY_ENABLE != 0) velocity_from_sample = FIXED_VELOCITY;
            else if (value >= VELOCITY_3_THRESHOLD) velocity_from_sample = 2'd3;
            else if (value >= VELOCITY_2_THRESHOLD) velocity_from_sample = 2'd2;
            else if (value >= VELOCITY_1_THRESHOLD) velocity_from_sample = 2'd1;
            else velocity_from_sample = 2'd0;
        end
    endfunction
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            pluck_valid <= 0;
            velocity_level <= {4{FIXED_VELOCITY}};
            raw_adc <= 0; peak_adc <= 0; event_timestamp <= 0;
            timestamp_count <= 0;
            armed <= 4'b1111;
            for (i = 0; i < 4; i = i + 1) begin
                dead_count[i] <= 0;
                settle_count[i] <= 0;
            end
        end
        else begin
            pluck_valid <= 0;
            timestamp_count <= timestamp_count + 1'b1;
            if (sample_valid) begin
                raw_adc[sample_string*12 +: 12] <= sample_data;
                if (magnitude > peak_adc[sample_string*12 +: 12])
                    peak_adc[sample_string*12 +: 12] <= magnitude;
                if (dead_count[sample_string] != 0)
                    dead_count[sample_string] <= dead_count[sample_string] - 1'b1;
                if (!armed[sample_string]) begin
                    if (magnitude <= REARM_THRESHOLD) begin
                        if (settle_count[sample_string] < SETTLE_SAMPLES)
                            settle_count[sample_string] <= settle_count[sample_string] + 1'b1;
                        if ((settle_count[sample_string] + 1 >= SETTLE_SAMPLES) &&
                            (dead_count[sample_string] == 0)) begin
                            armed[sample_string] <= 1'b1;
                            settle_count[sample_string] <= 0;
                            peak_adc[sample_string*12 +: 12] <= magnitude;
                        end
                    end
                    else settle_count[sample_string] <= 0;
                end
                else if (magnitude >= TRIGGER_THRESHOLD) begin
                    pluck_valid[sample_string] <= 1'b1;
                    velocity_level[sample_string*2 +: 2] <= velocity_from_sample(magnitude);
                    event_timestamp <= timestamp_count;
                    armed[sample_string] <= 1'b0;
                    dead_count[sample_string] <= DEAD_SAMPLES;
                    settle_count[sample_string] <= 0;
                    peak_adc[sample_string*12 +: 12] <= magnitude;
                end
            end
        end
    end
endmodule
