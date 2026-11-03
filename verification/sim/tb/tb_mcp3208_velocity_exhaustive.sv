`timescale 1ns/1ps

// Exhaustively verifies all four digital velocity classes on every string
// through the complete MCP3208 SPI reader and pluck detector path.
module tb_mcp3208_velocity_exhaustive;
    reg clk;
    reg rst_n;
    wire adc_cs_n;
    wire adc_sclk;
    wire adc_mosi;
    reg adc_miso;
    wire [3:0] pluck_valid;
    wire [7:0] velocity_level;
    wire [47:0] raw_adc;
    wire [47:0] peak_adc;
    wire [31:0] event_timestamp;

    reg [11:0] adc_value0;
    reg [11:0] adc_value1;
    reg [11:0] adc_value2;
    reg [11:0] adc_value3;
    reg [4:0] command_bits;
    reg [4:0] captured_command;
    reg [2:0] selected_channel;
    reg [11:0] selected_data;
    integer rising_count;
    integer command_error_count;
    integer event_count;
    reg [3:0] last_event_mask;
    reg [7:0] last_velocity;
    reg [31:0] last_timestamp;
    reg [31:0] previous_timestamp;
    integer string_index;
    integer level_index;

    mcp3208_pluck_frontend #(
        .SPI_CLK_DIV(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .pluck_valid(pluck_valid), .velocity_level(velocity_level),
        .raw_adc(raw_adc), .peak_adc(peak_adc),
        .event_timestamp(event_timestamp),.capture_pending()
    );

    always #5 clk = ~clk;

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

    function [11:0] adc_value_for_level;
        input integer level,channel;
        begin
            case(channel)
                0:case(level)0:adc_value_for_level=2273;1:adc_value_for_level=2333;2:adc_value_for_level=2483;default:adc_value_for_level=2673;endcase
                1:case(level)0:adc_value_for_level=2153;1:adc_value_for_level=2303;2:adc_value_for_level=2453;default:adc_value_for_level=2653;endcase
                2:case(level)0:adc_value_for_level=2113;1:adc_value_for_level=2203;2:adc_value_for_level=2333;default:adc_value_for_level=2453;endcase
                3:case(level)0:adc_value_for_level=2153;1:adc_value_for_level=2273;2:adc_value_for_level=2433;default:adc_value_for_level=2653;endcase
            endcase
        end
    endfunction

    task set_adc_value;
        input integer selected_string;
        input [11:0] value;
        begin
            case (selected_string)
                0: adc_value0 = value;
                1: adc_value1 = value;
                2: adc_value2 = value;
                default: adc_value3 = value;
            endcase
        end
    endtask

    always @(negedge adc_cs_n) begin
        command_bits = 5'd0;
        captured_command = 5'd0;
        selected_channel = 3'd0;
        selected_data = 12'd0;
        rising_count = 0;
        adc_miso = 1'b0;
    end

    always @(posedge adc_sclk) begin
        if (!adc_cs_n) begin
            if (rising_count < 5)
                command_bits[4-rising_count] = adc_mosi;
            if (rising_count == 4) begin
                captured_command = {command_bits[4:1], adc_mosi};
                if (captured_command[4:3] !== 2'b11)
                    command_error_count = command_error_count + 1;
                selected_channel = captured_command[2:0];
                selected_data = adc_value_for_channel(selected_channel);
            end
            rising_count = rising_count + 1;
        end
    end

    always @(negedge adc_sclk) begin
        if (!adc_cs_n) begin
            if ((rising_count >= 7) && (rising_count <= 18))
                adc_miso = selected_data[18-rising_count];
            else
                adc_miso = 1'b0;
        end
    end

    always @(posedge clk) begin
        #1;
        if (pluck_valid != 4'd0) begin
            if ((pluck_valid != 4'b0001) && (pluck_valid != 4'b0010) &&
                (pluck_valid != 4'b0100) && (pluck_valid != 4'b1000)) begin
                $display("FAIL: simultaneous/unexpected velocity events mask=%b",
                         pluck_valid);
                $fatal;
            end
            event_count = event_count + 1;
            last_event_mask = pluck_valid;
            last_velocity = velocity_level;
            last_timestamp = event_timestamp;
        end
    end

    task exercise_velocity;
        input integer selected_string;
        input integer expected_level;
        integer event_count_before;
        integer guard;
        reg [1:0] observed_level;
        begin
            set_adc_value(selected_string, 12'd2053);
            repeat (260000) @(posedge clk);

            event_count_before = event_count;
            set_adc_value(selected_string,
                          adc_value_for_level(expected_level,selected_string));
            guard = 0;
            while ((event_count == event_count_before) && (guard < 60000)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (event_count == event_count_before) begin
                $display("FAIL: velocity event timeout string=%0d level=%0d",
                         selected_string, expected_level);
                $fatal;
            end
            observed_level =
                (last_velocity >> (selected_string * 2)) & 2'b11;
            if ((last_event_mask !== (4'b0001 << selected_string)) ||
                (observed_level !== expected_level[1:0])) begin
                $display("FAIL: velocity mapping string=%0d expected=%0d got_mask=%b got_level=%0d",
                         selected_string, expected_level,
                         last_event_mask, observed_level);
                $fatal;
            end
            if ((previous_timestamp != 0) &&
                (last_timestamp <= previous_timestamp)) begin
                $display("FAIL: event timestamp did not increase previous=%0d current=%0d",
                         previous_timestamp, last_timestamp);
                $fatal;
            end
            previous_timestamp = last_timestamp;
            set_adc_value(selected_string, 12'd2053);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        adc_miso = 1'b0;
        adc_value0 = 12'd2053;
        adc_value1 = 12'd2053;
        adc_value2 = 12'd2053;
        adc_value3 = 12'd2053;
        command_bits = 5'd0;
        captured_command = 5'd0;
        selected_channel = 3'd0;
        selected_data = 12'd0;
        rising_count = 0;
        command_error_count = 0;
        event_count = 0;
        last_event_mask = 4'd0;
        last_velocity = 8'd0;
        last_timestamp = 32'd0;
        previous_timestamp = 32'd0;

        repeat (6) @(posedge clk);
        #1 rst_n = 1'b1;
        repeat (260000) @(posedge clk);

        for (string_index = 0; string_index < 4;
             string_index = string_index + 1)
            for (level_index = 0; level_index < 4;
                 level_index = level_index + 1)
                exercise_velocity(string_index, level_index);

        repeat (260000) @(posedge clk);
        if (event_count != 16) begin
            $display("FAIL: exhaustive velocity event count=%0d expected=16",
                     event_count);
            $fatal;
        end
        if (command_error_count != 0) begin
            $display("FAIL: exhaustive MCP3208 command errors=%0d",
                     command_error_count);
            $fatal;
        end
        if ((raw_adc[11:0] !== 12'd2053) ||
            (raw_adc[23:12] !== 12'd2053) ||
            (raw_adc[35:24] !== 12'd2053) ||
            (raw_adc[47:36] !== 12'd2053)) begin
            $display("FAIL: one or more ADC channels did not return below rearm threshold raw=%h",
                     raw_adc);
            $fatal;
        end

        $display("PASS: production MCP3208 SPI4/capture32/dead400/settle80 per-string calibration, all strings x levels events=%0d",
                 event_count);
        $finish;
    end

endmodule
