`timescale 1ns/1ps

module tb_mcp3208_pluck_frontend;

    reg clk;
    reg rst_n;
    wire adc_cs_n;
    wire adc_sclk;
    wire adc_mosi;
    reg  adc_miso;

    wire [3:0]  pluck_valid;
    wire [7:0]  velocity_level;
    wire [47:0] raw_adc;
    wire [47:0] peak_adc;
    wire [31:0] event_timestamp;

    reg [11:0] adc_value0;
    reg [11:0] adc_value1;
    reg [11:0] adc_value2;
    reg [11:0] adc_value3;
    reg [4:0]  command_bits;
    reg [4:0]  captured_command;
    reg [2:0]  selected_channel;
    reg [11:0] selected_data;
    integer    rising_count;
    integer    command_error_count;

    mcp3208_pluck_frontend #(
        .SPI_CLK_DIV (2),
        .DEAD_SAMPLES(2), .SETTLE_SAMPLES(2), .FIXED_VELOCITY_ENABLE(0)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .adc_cs_n       (adc_cs_n),
        .adc_sclk       (adc_sclk),
        .adc_mosi       (adc_mosi),
        .adc_miso       (adc_miso),
        .pluck_valid    (pluck_valid),
        .velocity_level (velocity_level),
        .raw_adc        (raw_adc),
        .peak_adc       (peak_adc),
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

    // MCP3208 model: receive five control bits on rising edges, then return
    // a null bit and 12 data bits, changing MISO on falling edges.
    always @(negedge adc_cs_n) begin
        command_bits     = 5'd0;
        captured_command = 5'd0;
        selected_channel = 3'd0;
        selected_data    = 12'd0;
        rising_count     = 0;
        adc_miso         = 1'b0;
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
                selected_data = adc_value_for_channel(captured_command[2:0]);
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

    reg [3:0] seen_plucks;
    reg [1:0] velocity0_at_event;
    reg [1:0] velocity1_at_event;
    reg [1:0] velocity2_at_event;
    reg [1:0] velocity3_at_event;
    integer event_count0;

    always @(posedge clk) begin
        if (pluck_valid[0]) begin
            seen_plucks[0] <= 1'b1;
            velocity0_at_event <= velocity_level[1:0];
            event_count0 <= event_count0 + 1;
        end
        if (pluck_valid[1]) begin
            seen_plucks[1] <= 1'b1;
            velocity1_at_event <= velocity_level[3:2];
        end
        if (pluck_valid[2]) begin
            seen_plucks[2] <= 1'b1;
            velocity2_at_event <= velocity_level[5:4];
        end
        if (pluck_valid[3]) begin
            seen_plucks[3] <= 1'b1;
            velocity3_at_event <= velocity_level[7:6];
        end
    end

    task wait_for_plucks;
        input [3:0] expected_mask;
        integer guard;
        begin
            guard = 0;
            while (seen_plucks !== expected_mask) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 60000) begin
                    $display("FAIL: pluck timeout mask=%b expected=%b",
                             seen_plucks, expected_mask);
                    $finish;
                end
            end
        end
    endtask

    task wait_for_string0_events;
        input integer expected_count;
        integer guard;
        begin
            guard = 0;
            while (event_count0 < expected_count) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 60000) begin
                    $display("FAIL: string 0 retrigger timeout count=%0d", event_count0);
                    $finish;
                end
            end
        end
    endtask

    initial begin
        clk                 = 1'b0;
        rst_n               = 1'b0;
        adc_miso            = 1'b0;
        adc_value0          = 12'd2273;
        adc_value1          = 12'd2303;
        adc_value2          = 12'd2333;
        adc_value3          = 12'd2653;
        command_bits        = 5'd0;
        captured_command    = 5'd0;
        selected_channel    = 3'd0;
        selected_data       = 12'd0;
        rising_count        = 0;
        command_error_count = 0;
        seen_plucks         = 4'd0;
        velocity0_at_event  = 2'd0;
        velocity1_at_event  = 2'd0;
        velocity2_at_event  = 2'd0;
        velocity3_at_event  = 2'd0;
        event_count0        = 0;

        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;

        wait_for_plucks(4'b1111);
        #1;
        if ((velocity0_at_event !== 2'd0) ||
            (velocity1_at_event !== 2'd1) ||
            (velocity2_at_event !== 2'd2) ||
            (velocity3_at_event !== 2'd3)) begin
            $display("FAIL: four-level velocity mapping %d %d %d %d",
                     velocity0_at_event, velocity1_at_event,
                     velocity2_at_event, velocity3_at_event);
            $finish;
        end
        if ((raw_adc[11:0] !== 12'd2273) ||
            (raw_adc[23:12] !== 12'd2303) ||
            (raw_adc[35:24] !== 12'd2333) ||
            (raw_adc[47:36] !== 12'd2653)) begin
            $display("FAIL: MCP3208 channel sample ordering");
            $finish;
        end

        // Let string 0 fall below the rearm threshold for more than its
        // two-sample dead time, then verify a new pluck can be emitted.
        adc_value0 = 12'd2053;
        repeat (1000) @(posedge clk);
        adc_value0 = 12'd2333;

        wait_for_string0_events(2);
        #1;
        if (velocity0_at_event !== 2'd1) begin
            $display("FAIL: string 0 retrigger velocity=%d", velocity0_at_event);
            $finish;
        end
        if (command_error_count != 0) begin
            $display("FAIL: MCP3208 command errors=%0d", command_error_count);
            $finish;
        end

        $display("PASS: MCP3208 four-channel samples, velocity and retrigger");
        $finish;
    end

endmodule
