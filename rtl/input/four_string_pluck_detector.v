`include "../config/guitar_config.vh"

// Per-string envelope trigger with hysteresis, peak observation, and dead time.
module four_string_pluck_detector #(
    parameter [11:0] TRIGGER_THRESHOLD = `PLUCK_TRIGGER_THRESHOLD,
    parameter [11:0] REARM_THRESHOLD   = `PLUCK_REARM_THRESHOLD,
    parameter [11:0] VELOCITY_1_THRESHOLD = `VELOCITY_LEVEL_1_THRESHOLD,
    parameter [11:0] VELOCITY_2_THRESHOLD = `VELOCITY_LEVEL_2_THRESHOLD,
    parameter [11:0] VELOCITY_3_THRESHOLD = `VELOCITY_LEVEL_3_THRESHOLD,
    parameter integer DEAD_SAMPLES = `RETRIGGER_DEAD_SAMPLES
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [1:0]  sample_string,
    input  wire [11:0] sample_data,

    output reg  [3:0]  pluck_valid,
    output reg  [7:0]  velocity_level,
    output reg [47:0]  raw_adc,
    output reg [47:0]  peak_adc,
    output reg [31:0]  event_timestamp
);

    reg [3:0] armed;
    reg [15:0] dead_count0;
    reg [15:0] dead_count1;
    reg [15:0] dead_count2;
    reg [15:0] dead_count3;
    reg [31:0] timestamp_count;

    function [1:0] velocity_from_sample;
        input [11:0] value;
        begin
            if (value >= VELOCITY_3_THRESHOLD)
                velocity_from_sample = 2'd3;
            else if (value >= VELOCITY_2_THRESHOLD)
                velocity_from_sample = 2'd2;
            else if (value >= VELOCITY_1_THRESHOLD)
                velocity_from_sample = 2'd1;
            else
                velocity_from_sample = 2'd0;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            pluck_valid    <= 4'd0;
            velocity_level <= 8'd0;
            raw_adc        <= 48'd0;
            peak_adc       <= 48'd0;
            event_timestamp <= 32'd0;
            armed          <= 4'b1111;
            dead_count0    <= 16'd0;
            dead_count1    <= 16'd0;
            dead_count2    <= 16'd0;
            dead_count3    <= 16'd0;
            timestamp_count <= 32'd0;
        end
        else begin
            pluck_valid    <= 4'd0;
            timestamp_count <= timestamp_count + 1'b1;

            if (sample_valid) begin
                case (sample_string)
                    2'd0: begin
                        raw_adc[11:0] <= sample_data;
                        if (dead_count0 != 0)
                            dead_count0 <= dead_count0 - 1'b1;
                        if (!armed[0] && sample_data <= REARM_THRESHOLD) begin
                            armed[0]    <= 1'b1;
                            peak_adc[11:0] <= sample_data;
                        end
                        else if (armed[0]) begin
                            if (sample_data > peak_adc[11:0])
                                peak_adc[11:0] <= sample_data;
                            if ((sample_data >= TRIGGER_THRESHOLD) &&
                                (dead_count0 == 0)) begin
                                pluck_valid[0] <= 1'b1;
                                velocity_level[1:0] <= velocity_from_sample(sample_data);
                                event_timestamp <= timestamp_count;
                                armed[0] <= 1'b0;
                                dead_count0 <= DEAD_SAMPLES;
                            end
                        end
                    end

                    2'd1: begin
                        raw_adc[23:12] <= sample_data;
                        if (dead_count1 != 0)
                            dead_count1 <= dead_count1 - 1'b1;
                        if (!armed[1] && sample_data <= REARM_THRESHOLD) begin
                            armed[1]      <= 1'b1;
                            peak_adc[23:12] <= sample_data;
                        end
                        else if (armed[1]) begin
                            if (sample_data > peak_adc[23:12])
                                peak_adc[23:12] <= sample_data;
                            if ((sample_data >= TRIGGER_THRESHOLD) &&
                                (dead_count1 == 0)) begin
                                pluck_valid[1] <= 1'b1;
                                velocity_level[3:2] <= velocity_from_sample(sample_data);
                                event_timestamp <= timestamp_count;
                                armed[1] <= 1'b0;
                                dead_count1 <= DEAD_SAMPLES;
                            end
                        end
                    end

                    2'd2: begin
                        raw_adc[35:24] <= sample_data;
                        if (dead_count2 != 0)
                            dead_count2 <= dead_count2 - 1'b1;
                        if (!armed[2] && sample_data <= REARM_THRESHOLD) begin
                            armed[2]      <= 1'b1;
                            peak_adc[35:24] <= sample_data;
                        end
                        else if (armed[2]) begin
                            if (sample_data > peak_adc[35:24])
                                peak_adc[35:24] <= sample_data;
                            if ((sample_data >= TRIGGER_THRESHOLD) &&
                                (dead_count2 == 0)) begin
                                pluck_valid[2] <= 1'b1;
                                velocity_level[5:4] <= velocity_from_sample(sample_data);
                                event_timestamp <= timestamp_count;
                                armed[2] <= 1'b0;
                                dead_count2 <= DEAD_SAMPLES;
                            end
                        end
                    end

                    default: begin
                        raw_adc[47:36] <= sample_data;
                        if (dead_count3 != 0)
                            dead_count3 <= dead_count3 - 1'b1;
                        if (!armed[3] && sample_data <= REARM_THRESHOLD) begin
                            armed[3]      <= 1'b1;
                            peak_adc[47:36] <= sample_data;
                        end
                        else if (armed[3]) begin
                            if (sample_data > peak_adc[47:36])
                                peak_adc[47:36] <= sample_data;
                            if ((sample_data >= TRIGGER_THRESHOLD) &&
                                (dead_count3 == 0)) begin
                                pluck_valid[3] <= 1'b1;
                                velocity_level[7:6] <= velocity_from_sample(sample_data);
                                event_timestamp <= timestamp_count;
                                armed[3] <= 1'b0;
                                dead_count3 <= DEAD_SAMPLES;
                            end
                        end
                    end
                endcase
            end
        end
    end

endmodule
