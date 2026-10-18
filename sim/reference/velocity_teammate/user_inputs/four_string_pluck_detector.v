`include "../config/guitar_config.vh"

// Four-channel piezo trigger.  A threshold crossing opens a short capture
// window; the largest absolute excursion in that window selects velocity.
module four_string_pluck_detector #(
    parameter [11:0] TRIGGER_THRESHOLD_CH0 = `PLUCK_TRIGGER_THRESHOLD_CH0,
    parameter [11:0] TRIGGER_THRESHOLD_CH1 = `PLUCK_TRIGGER_THRESHOLD_CH1,
    parameter [11:0] TRIGGER_THRESHOLD_CH2 = `PLUCK_TRIGGER_THRESHOLD_CH2,
    parameter [11:0] TRIGGER_THRESHOLD_CH3 = `PLUCK_TRIGGER_THRESHOLD_CH3,
    parameter [11:0] REARM_THRESHOLD_CH0 = `PLUCK_REARM_THRESHOLD_CH0,
    parameter [11:0] REARM_THRESHOLD_CH1 = `PLUCK_REARM_THRESHOLD_CH1,
    parameter [11:0] REARM_THRESHOLD_CH2 = `PLUCK_REARM_THRESHOLD_CH2,
    parameter [11:0] REARM_THRESHOLD_CH3 = `PLUCK_REARM_THRESHOLD_CH3,
    parameter [11:0] BASELINE_CODE_CH0 = `ADC_BASELINE_CODE_CH0,
    parameter [11:0] BASELINE_CODE_CH1 = `ADC_BASELINE_CODE_CH1,
    parameter [11:0] BASELINE_CODE_CH2 = `ADC_BASELINE_CODE_CH2,
    parameter [11:0] BASELINE_CODE_CH3 = `ADC_BASELINE_CODE_CH3,
    parameter USE_ABSOLUTE_DELTA = 1'b1,
    parameter integer DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES,
    parameter integer SETTLE_SAMPLES = `PLUCK_SETTLE_SAMPLES,
    parameter integer CAPTURE_SAMPLES = `VELOCITY_CAPTURE_SAMPLES,
    parameter integer FIXED_VELOCITY_ENABLE = `BOARD_FIXED_VELOCITY_ENABLE,
    parameter [1:0] FIXED_VELOCITY = `BOARD_FIXED_VELOCITY,
    parameter [11:0] VELOCITY_1_THRESHOLD_CH0 = `VELOCITY_LEVEL_1_THRESHOLD_CH0,
    parameter [11:0] VELOCITY_1_THRESHOLD_CH1 = `VELOCITY_LEVEL_1_THRESHOLD_CH1,
    parameter [11:0] VELOCITY_1_THRESHOLD_CH2 = `VELOCITY_LEVEL_1_THRESHOLD_CH2,
    parameter [11:0] VELOCITY_1_THRESHOLD_CH3 = `VELOCITY_LEVEL_1_THRESHOLD_CH3,
    parameter [11:0] VELOCITY_2_THRESHOLD_CH0 = `VELOCITY_LEVEL_2_THRESHOLD_CH0,
    parameter [11:0] VELOCITY_2_THRESHOLD_CH1 = `VELOCITY_LEVEL_2_THRESHOLD_CH1,
    parameter [11:0] VELOCITY_2_THRESHOLD_CH2 = `VELOCITY_LEVEL_2_THRESHOLD_CH2,
    parameter [11:0] VELOCITY_2_THRESHOLD_CH3 = `VELOCITY_LEVEL_2_THRESHOLD_CH3,
    parameter [11:0] VELOCITY_3_THRESHOLD_CH0 = `VELOCITY_LEVEL_3_THRESHOLD_CH0,
    parameter [11:0] VELOCITY_3_THRESHOLD_CH1 = `VELOCITY_LEVEL_3_THRESHOLD_CH1,
    parameter [11:0] VELOCITY_3_THRESHOLD_CH2 = `VELOCITY_LEVEL_3_THRESHOLD_CH2,
    parameter [11:0] VELOCITY_3_THRESHOLD_CH3 = `VELOCITY_LEVEL_3_THRESHOLD_CH3
) (
    input wire clk,
    input wire rst_n,
    input wire sample_valid,
    input wire [1:0] sample_string,
    input wire [11:0] sample_data,
    output reg [3:0] pluck_valid,
    output reg [7:0] velocity_level,
    output reg [47:0] raw_adc,
    output reg [47:0] peak_adc,
    output reg [31:0] event_timestamp
);
    reg [3:0] armed;
    reg [3:0] capturing;
    reg [15:0] dead_count [0:3];
    reg [15:0] settle_count [0:3];
    reg [15:0] capture_count [0:3];
    reg [47:0] capture_peak;
    reg [31:0] timestamp_count;

    function [11:0] baseline_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: baseline_for_string = BASELINE_CODE_CH0;
                2'd1: baseline_for_string = BASELINE_CODE_CH1;
                2'd2: baseline_for_string = BASELINE_CODE_CH2;
                default: baseline_for_string = BASELINE_CODE_CH3;
            endcase
        end
    endfunction

    function [11:0] trigger_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: trigger_for_string = TRIGGER_THRESHOLD_CH0;
                2'd1: trigger_for_string = TRIGGER_THRESHOLD_CH1;
                2'd2: trigger_for_string = TRIGGER_THRESHOLD_CH2;
                default: trigger_for_string = TRIGGER_THRESHOLD_CH3;
            endcase
        end
    endfunction

    function [11:0] rearm_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: rearm_for_string = REARM_THRESHOLD_CH0;
                2'd1: rearm_for_string = REARM_THRESHOLD_CH1;
                2'd2: rearm_for_string = REARM_THRESHOLD_CH2;
                default: rearm_for_string = REARM_THRESHOLD_CH3;
            endcase
        end
    endfunction

    function [11:0] velocity_1_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: velocity_1_for_string = VELOCITY_1_THRESHOLD_CH0;
                2'd1: velocity_1_for_string = VELOCITY_1_THRESHOLD_CH1;
                2'd2: velocity_1_for_string = VELOCITY_1_THRESHOLD_CH2;
                default: velocity_1_for_string = VELOCITY_1_THRESHOLD_CH3;
            endcase
        end
    endfunction

    function [11:0] velocity_2_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: velocity_2_for_string = VELOCITY_2_THRESHOLD_CH0;
                2'd1: velocity_2_for_string = VELOCITY_2_THRESHOLD_CH1;
                2'd2: velocity_2_for_string = VELOCITY_2_THRESHOLD_CH2;
                default: velocity_2_for_string = VELOCITY_2_THRESHOLD_CH3;
            endcase
        end
    endfunction

    function [11:0] velocity_3_for_string;
        input [1:0] string_id;
        begin
            case (string_id)
                2'd0: velocity_3_for_string = VELOCITY_3_THRESHOLD_CH0;
                2'd1: velocity_3_for_string = VELOCITY_3_THRESHOLD_CH1;
                2'd2: velocity_3_for_string = VELOCITY_3_THRESHOLD_CH2;
                default: velocity_3_for_string = VELOCITY_3_THRESHOLD_CH3;
            endcase
        end
    endfunction

    wire [11:0] baseline_value = baseline_for_string(sample_string);
    wire [11:0] magnitude = !USE_ABSOLUTE_DELTA ? sample_data :
        (sample_data >= baseline_value ? sample_data - baseline_value :
                                        baseline_value - sample_data);

    function [1:0] velocity_from_peak;
        input [11:0] value;
        input [1:0] string_id;
        begin
            if (FIXED_VELOCITY_ENABLE != 0)
                velocity_from_peak = FIXED_VELOCITY;
            else if (value >= velocity_3_for_string(string_id))
                velocity_from_peak = 2'd3;
            else if (value >= velocity_2_for_string(string_id))
                velocity_from_peak = 2'd2;
            else if (value >= velocity_1_for_string(string_id))
                velocity_from_peak = 2'd1;
            else
                velocity_from_peak = 2'd0;
        end
    endfunction

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            pluck_valid     <= 4'd0;
            velocity_level  <= {4{FIXED_VELOCITY}};
            raw_adc         <= 48'd0;
            peak_adc        <= 48'd0;
            capture_peak    <= 48'd0;
            event_timestamp <= 32'd0;
            timestamp_count <= 32'd0;
            armed           <= 4'b1111;
            capturing       <= 4'd0;
            for (i = 0; i < 4; i = i + 1) begin
                dead_count[i]    <= 16'd0;
                settle_count[i]  <= 16'd0;
                capture_count[i] <= 16'd0;
            end
        end else begin
            pluck_valid     <= 4'd0;
            timestamp_count <= timestamp_count + 1'b1;

            if (sample_valid) begin
                raw_adc[sample_string*12 +: 12] <= sample_data;
                if (magnitude > peak_adc[sample_string*12 +: 12])
                    peak_adc[sample_string*12 +: 12] <= magnitude;

                if (dead_count[sample_string] != 0)
                    dead_count[sample_string] <= dead_count[sample_string] - 1'b1;

                if (capturing[sample_string]) begin
                    if (capture_count[sample_string] >= CAPTURE_SAMPLES - 1) begin
                        pluck_valid[sample_string] <= 1'b1;
                        if (magnitude > capture_peak[sample_string*12 +: 12]) begin
                            velocity_level[sample_string*2 +: 2] <= velocity_from_peak(magnitude, sample_string);
                            capture_peak[sample_string*12 +: 12] <= magnitude;
                        end else begin
                            velocity_level[sample_string*2 +: 2] <=
                                velocity_from_peak(capture_peak[sample_string*12 +: 12], sample_string);
                        end
                        event_timestamp <= timestamp_count;
                        capturing[sample_string] <= 1'b0;
                        armed[sample_string] <= 1'b0;
                        dead_count[sample_string] <= DEAD_SAMPLES;
                        settle_count[sample_string] <= 16'd0;
                        capture_count[sample_string] <= 16'd0;
                    end else begin
                        capture_count[sample_string] <= capture_count[sample_string] + 1'b1;
                        if (magnitude > capture_peak[sample_string*12 +: 12])
                            capture_peak[sample_string*12 +: 12] <= magnitude;
                    end
                end else if (!armed[sample_string]) begin
                    if (magnitude <= rearm_for_string(sample_string)) begin
                        if (settle_count[sample_string] < SETTLE_SAMPLES)
                            settle_count[sample_string] <= settle_count[sample_string] + 1'b1;
                        if ((settle_count[sample_string] + 1 >= SETTLE_SAMPLES) &&
                            (dead_count[sample_string] == 0)) begin
                            armed[sample_string] <= 1'b1;
                            settle_count[sample_string] <= 16'd0;
                            peak_adc[sample_string*12 +: 12] <= magnitude;
                            capture_peak[sample_string*12 +: 12] <= magnitude;
                        end
                    end else begin
                        settle_count[sample_string] <= 16'd0;
                    end
                end else if (magnitude >= trigger_for_string(sample_string)) begin
                    capturing[sample_string] <= 1'b1;
                    capture_count[sample_string] <= 16'd0;
                    capture_peak[sample_string*12 +: 12] <= magnitude;
                    settle_count[sample_string] <= 16'd0;
                end
            end
        end
    end
endmodule
