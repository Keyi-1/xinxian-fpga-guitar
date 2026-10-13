`timescale 1ns/1ps

// Measures the README internal digital latency at real clock/divider values.
// The measurement starts when the ADC detector emits pluck_valid and ends
// when the first nonzero PCM16 sample is presented to the PT8211 transmitter.
module tb_guitar_audio_latency;

    localparam integer LATENCY_LIMIT_NS = 5000000;
    localparam integer STREAM_SAMPLES   = 128;
    localparam integer REPEAT_ROUNDS    = 8;

    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg rst_n;
    reg adc_miso;
    reg [11:0] adc_value0;
    reg [11:0] adc_value1;
    reg [11:0] adc_value2;
    reg [11:0] adc_value3;

    wire sine_adc_cs_n;
    wire sine_adc_sclk;
    wire sine_adc_mosi;
    wire harmonic_adc_cs_n;
    wire harmonic_adc_sclk;
    wire harmonic_adc_mosi;
    wire [3:0] sine_voice_active;
    wire [3:0] harmonic_voice_active;

    guitar_audio_top #(
        .SAMPLE_DIV      (256),
        .PT8211_REF_DIV  (4),
        .ADC_SPI_CLK_DIV(4),
        .USE_HARMONIC    (0)
    ) u_sine_top (
        .rock_select(1'b0),
        .sys_clk_50m       (sys_clk_50m),
        .audio_clk_12m288  (audio_clk_12m288),
        .rst_n             (rst_n),
        .fret_col_in_n     (8'hff),
        .adc_cs_n          (sine_adc_cs_n),
        .adc_sclk          (sine_adc_sclk),
        .adc_mosi          (sine_adc_mosi),
        .adc_miso          (adc_miso),
        .timbre_select     (1'b0),
        .chorus_enable     (1'b0),
        .sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .fret_row_oe       (),
        .fret_row_drive_n  (),
        .dac_bclk          (),
        .dac_lrck          (),
        .dac_din           (),
        .stable_fret_mask  (),
        .stable_fret_id    (),
        .audio_voice_active(sine_voice_active),
        .velocity_level    (),
        .raw_adc           (),
        .peak_adc          (),
        .event_timestamp   (),
        .final_pcm_valid   (),
        .pluck_events(),
        .final_pcm         ()
    ,
        .display_phase_inc(),.display_note_on(),.display_sample_tick(),.display_voice_sample_valid(),.display_voice_pcm(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );

    guitar_audio_top #(
        .SAMPLE_DIV      (256),
        .PT8211_REF_DIV  (4),
        .ADC_SPI_CLK_DIV(4),
        .USE_HARMONIC    (1)
    ) u_harmonic_top (
        .rock_select(1'b0),
        .sys_clk_50m       (sys_clk_50m),
        .audio_clk_12m288  (audio_clk_12m288),
        .rst_n             (rst_n),
        .fret_col_in_n     (8'hff),
        .adc_cs_n          (harmonic_adc_cs_n),
        .adc_sclk          (harmonic_adc_sclk),
        .adc_mosi          (harmonic_adc_mosi),
        .adc_miso          (adc_miso),
        .timbre_select     (1'b0),
        .chorus_enable     (1'b0),
        .sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .fret_row_oe       (),
        .fret_row_drive_n  (),
        .dac_bclk          (),
        .dac_lrck          (),
        .dac_din           (),
        .stable_fret_mask  (),
        .stable_fret_id    (),
        .audio_voice_active(harmonic_voice_active),
        .velocity_level    (),
        .raw_adc           (),
        .peak_adc          (),
        .event_timestamp   (),
        .final_pcm_valid   (),
        .pluck_events(),
        .final_pcm         ()
    ,
        .display_phase_inc(),.display_note_on(),.display_sample_tick(),.display_voice_sample_valid(),.display_voice_pcm(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );

    always #10 sys_clk_50m = ~sys_clk_50m;
    always #40.690104167 audio_clk_12m288 = ~audio_clk_12m288;

    function [11:0] adc_value_for_channel;
        input [2:0] channel;
        begin
            case (channel)
                3'd0: adc_value_for_channel = adc_value0;
                3'd1: adc_value_for_channel = adc_value1;
                3'd2: adc_value_for_channel = adc_value2;
                default: adc_value_for_channel = adc_value3;
            endcase
        end
    endfunction

    reg [4:0] adc_command;
    reg [2:0] adc_channel;
    reg [11:0] adc_selected_data;
    integer adc_rising_count;

    always @(negedge sine_adc_cs_n) begin
        adc_command = 5'd0;
        adc_channel = 3'd0;
        adc_selected_data = 12'd0;
        adc_rising_count = 0;
        adc_miso = 1'b0;
    end

    always @(posedge sine_adc_sclk) begin
        if (!sine_adc_cs_n) begin
            if (adc_rising_count < 5)
                adc_command[4-adc_rising_count] = sine_adc_mosi;
            if (adc_rising_count == 4) begin
                adc_channel = {adc_command[2:1], sine_adc_mosi};
                adc_selected_data = adc_value_for_channel(
                    {adc_command[2:1], sine_adc_mosi}
                );
            end
            adc_rising_count = adc_rising_count + 1;
        end
    end

    always @(negedge sine_adc_sclk) begin
        if (!sine_adc_cs_n) begin
            if ((adc_rising_count >= 7) && (adc_rising_count <= 18))
                adc_miso = adc_selected_data[18-adc_rising_count];
            else
                adc_miso = 1'b0;
        end
    end

    wire sine_pcm16_valid =
        u_sine_top.u_board_audio_chain.pcm16_left_valid;
    wire signed [15:0] sine_pcm16 =
        (u_sine_top.u_board_audio_chain.pcm16_left_out != 0) ? u_sine_top.u_board_audio_chain.pcm16_left_out : u_sine_top.u_board_audio_chain.pcm16_right_out;
    wire harmonic_pcm16_valid =
        u_harmonic_top.u_board_audio_chain.pcm16_left_valid;
    wire signed [15:0] harmonic_pcm16 =
        (u_harmonic_top.u_board_audio_chain.pcm16_left_out != 0) ? u_harmonic_top.u_board_audio_chain.pcm16_left_out : u_harmonic_top.u_board_audio_chain.pcm16_right_out;
    wire [3:0] harmonic_deadline_miss =
        u_harmonic_top.u_board_audio_chain.deadline_miss;

    reg measurement_active;
    integer current_string;
    time pluck_time;
    time sine_first_nonzero_time;
    time harmonic_first_nonzero_time;
    time sine_previous_valid_time;
    time harmonic_previous_valid_time;
    integer sine_stream_count;
    integer harmonic_stream_count;
    integer stream_interval_errors;
    time maximum_sine_latency;
    time maximum_harmonic_latency;
    integer measurement_count;

    always @(posedge sys_clk_50m) begin
        #1;
        if (rst_n &&
            ((sine_adc_cs_n !== harmonic_adc_cs_n) ||
             (sine_adc_sclk !== harmonic_adc_sclk) ||
             (sine_adc_mosi !== harmonic_adc_mosi))) begin
            $display("FAIL: sine/harmonic ADC frontends lost synchronization");
            $finish;
        end
    end

    always @(posedge audio_clk_12m288) begin
        #1;
        if (measurement_active) begin
            if (sine_pcm16_valid) begin
                if (sine_stream_count > 0 &&
                    ((($time - sine_previous_valid_time) < 20832) ||
                     (($time - sine_previous_valid_time) > 20835)))
                    stream_interval_errors = stream_interval_errors + 1;
                sine_previous_valid_time = $time;
                sine_stream_count = sine_stream_count + 1;
                if ((sine_first_nonzero_time == 0) &&
                    (sine_pcm16 != 16'sd0))
                    sine_first_nonzero_time = $time;
            end

            if (harmonic_pcm16_valid) begin
                if (harmonic_stream_count > 0 &&
                    ((($time - harmonic_previous_valid_time) < 20832) ||
                     (($time - harmonic_previous_valid_time) > 20835)))
                    stream_interval_errors = stream_interval_errors + 1;
                harmonic_previous_valid_time = $time;
                harmonic_stream_count = harmonic_stream_count + 1;
                if ((harmonic_first_nonzero_time == 0) &&
                    (harmonic_pcm16 != 16'sd0))
                    harmonic_first_nonzero_time = $time;
            end

            if (harmonic_deadline_miss !== 4'd0) begin
                $display("FAIL: harmonic deadline miss during latency test mask=%b",
                         harmonic_deadline_miss);
                $finish;
            end
        end
    end

    task clear_adc_values;
        begin
            adc_value0 = 12'd2053;
            adc_value1 = 12'd2053;
            adc_value2 = 12'd2053;
            adc_value3 = 12'd2053;
        end
    endtask

    task set_adc_value;
        input integer string_index;
        input [11:0] value;
        begin
            case (string_index)
                0: adc_value0 = value;
                1: adc_value1 = value;
                2: adc_value2 = value;
                default: adc_value3 = value;
            endcase
        end
    endtask

    task reset_paths;
        begin
            measurement_active = 1'b0;
            rst_n = 1'b0;
            clear_adc_values;
            repeat (12) @(posedge sys_clk_50m);
            repeat (4) @(posedge audio_clk_12m288);
            #1 rst_n = 1'b1;
            repeat (4) @(posedge sys_clk_50m);
        end
    endtask

    task measure_string;
        input integer string_index;
        integer guard;
        time sine_latency;
        time harmonic_latency;
        begin
            reset_paths;

            current_string = string_index;
            sine_first_nonzero_time = 0;
            harmonic_first_nonzero_time = 0;
            sine_previous_valid_time = 0;
            harmonic_previous_valid_time = 0;
            sine_stream_count = 0;
            harmonic_stream_count = 0;
            stream_interval_errors = 0;

            set_adc_value(string_index, 12'd2853);

            guard = 0;
            while (((u_sine_top.pluck_valid_audio[string_index] !== 1'b1) ||
                    (u_harmonic_top.pluck_valid_audio[string_index] !== 1'b1)) &&
                   (guard < 200000)) begin
                @(posedge sys_clk_50m);
                #1;
                guard = guard + 1;
            end
            if (guard >= 200000) begin
                $display("FAIL: ADC pluck timeout string=%0d", string_index);
                $finish;
            end

            pluck_time = $time;
            measurement_active = 1'b1;

            guard = 0;
            while (((sine_first_nonzero_time == 0) ||
                    (harmonic_first_nonzero_time == 0) ||
                    (sine_stream_count < STREAM_SAMPLES) ||
                    (harmonic_stream_count < STREAM_SAMPLES)) &&
                   (guard < 1000000)) begin
                @(posedge sys_clk_50m);
                #1;
                guard = guard + 1;
            end

            if ((sine_first_nonzero_time == 0) ||
                (harmonic_first_nonzero_time == 0)) begin
                $display("FAIL: first nonzero PCM timeout string=%0d", string_index);
                $finish;
            end

            sine_latency = sine_first_nonzero_time - pluck_time;
            harmonic_latency = harmonic_first_nonzero_time - pluck_time;

            if ((sine_latency > LATENCY_LIMIT_NS) ||
                (harmonic_latency > LATENCY_LIMIT_NS)) begin
                $display("FAIL: latency exceeds 5 ms string=%0d sine_ns=%0d harmonic_ns=%0d",
                         string_index, sine_latency, harmonic_latency);
                $finish;
            end
            if ((sine_voice_active !== (4'b0001 << string_index)) ||
                (harmonic_voice_active !== (4'b0001 << string_index))) begin
                $display("FAIL: wrong active voice string=%0d sine=%b harmonic=%b",
                         string_index, sine_voice_active,
                         harmonic_voice_active);
                $finish;
            end
            if (stream_interval_errors != 0) begin
                $display("FAIL: dropped/irregular PCM samples string=%0d errors=%0d",
                         string_index, stream_interval_errors);
                $finish;
            end

            if (sine_latency > maximum_sine_latency)
                maximum_sine_latency = sine_latency;
            if (harmonic_latency > maximum_harmonic_latency)
                maximum_harmonic_latency = harmonic_latency;

            $display("INFO: string=%0d sine_latency_ns=%0d harmonic_latency_ns=%0d stream_samples=%0d/%0d",
                     string_index, sine_latency, harmonic_latency,
                     sine_stream_count, harmonic_stream_count);
            measurement_active = 1'b0;
        end
    endtask

    integer string_index;
    integer round_index;

    initial begin
        sys_clk_50m = 1'b0;
        audio_clk_12m288 = 1'b0;
        rst_n = 1'b0;
        adc_miso = 1'b0;
        adc_command = 5'd0;
        adc_channel = 3'd0;
        adc_selected_data = 12'd0;
        adc_rising_count = 0;
        measurement_active = 1'b0;
        current_string = 0;
        pluck_time = 0;
        sine_first_nonzero_time = 0;
        harmonic_first_nonzero_time = 0;
        sine_previous_valid_time = 0;
        harmonic_previous_valid_time = 0;
        sine_stream_count = 0;
        harmonic_stream_count = 0;
        stream_interval_errors = 0;
        maximum_sine_latency = 0;
        maximum_harmonic_latency = 0;
        measurement_count = 0;
        clear_adc_values;

        for (round_index = 0; round_index < REPEAT_ROUNDS;
             round_index = round_index + 1) begin
            for (string_index = 0; string_index < 4;
                 string_index = string_index + 1) begin
                measure_string(string_index);
                measurement_count = measurement_count + 1;
            end
        end

        if (measurement_count < 30) begin
            $display("FAIL: latency repetitions=%0d expected_at_least=30",
                     measurement_count);
            $fatal;
        end

        $display("PASS: real-clock four-string ADC-to-PT8211-queue latency measurements=%0d sine_max_ns=%0d harmonic_max_ns=%0d",
                 measurement_count, maximum_sine_latency,
                 maximum_harmonic_latency);
        $finish;
    end

endmodule
