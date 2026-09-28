`timescale 1ns/1ps

module tb_neo_row0_led_test;

    localparam integer SAMPLE_CYCLES = 250000;

    reg        sys_clk_50m;
    reg        rst_n;
    reg  [7:0] col_in_n;
    wire [7:0] led;

    integer index;

    neo_row0_led_test dut (
        .sys_clk_50m(sys_clk_50m),
        .rst_n      (rst_n),
        .COL0       (col_in_n[0]),
        .COL1       (col_in_n[1]),
        .COL2       (col_in_n[2]),
        .COL3       (col_in_n[3]),
        .COL4       (col_in_n[4]),
        .COL5       (col_in_n[5]),
        .COL6       (col_in_n[6]),
        .COL7       (col_in_n[7]),
        .LED0       (led[0]),
        .LED1       (led[1]),
        .LED2       (led[2]),
        .LED3       (led[3]),
        .LED4       (led[4]),
        .LED5       (led[5]),
        .LED6       (led[6]),
        .LED7       (led[7])
    );

    always #10 sys_clk_50m = ~sys_clk_50m;

    task wait_debounced;
        begin
            repeat (2 * SAMPLE_CYCLES + 8) @(posedge sys_clk_50m);
            #1;
        end
    endtask

    task expect_led;
        input [7:0] expected;
        input [127:0] label_text;
        begin
            if (led !== expected) begin
                $display(
                    "FAIL: %0s led=%02h expected=%02h",
                    label_text,
                    led,
                    expected
                );
                $finish;
            end
        end
    endtask

    initial begin
        sys_clk_50m = 1'b0;
        rst_n       = 1'b0;
        col_in_n    = 8'hff;

        repeat (5) @(posedge sys_clk_50m);
        #1;
        expect_led(8'h00, "reset clears LEDs");

        rst_n = 1'b1;
        wait_debounced();
        expect_led(8'h00, "all columns high");

        // 每个低有效 COL 必须只点亮同编号 LED。
        for (index = 0; index < 8; index = index + 1) begin
            col_in_n = ~(8'h01 << index);
            wait_debounced();
            expect_led(8'h01 << index, "single column mapping");
        end

        // 多列同时按下必须同时显示，不能只保留一列。
        col_in_n = 8'b01011010;
        wait_debounced();
        expect_led(~8'b01011010, "multiple columns");

        // 少于一个 5 ms 采样周期的变化不得更新稳定输出。
        col_in_n = 8'hff;
        wait_debounced();
        expect_led(8'h00, "return to idle");

        col_in_n = 8'hfe;
        repeat (SAMPLE_CYCLES / 2) @(posedge sys_clk_50m);
        col_in_n = 8'hff;
        repeat (SAMPLE_CYCLES + 8) @(posedge sys_clk_50m);
        #1;
        expect_led(8'h00, "short pulse rejected");

        // 稳定低电平经过约 10 ms 后必须被接受并保持。
        col_in_n = 8'hf7;
        wait_debounced();
        expect_led(8'h08, "debounced stable state");
        repeat (SAMPLE_CYCLES) @(posedge sys_clk_50m);
        #1;
        expect_led(8'h08, "stable state retained");

        // KEY0 运行中复位必须异步熄灭全部 LED。
        rst_n = 1'b0;
        #1;
        expect_led(8'h00, "runtime reset clears LEDs");

        $display(
            "PASS: ROW0 columns debounce, mapping, multi-press and reset"
        );
        $finish;
    end

    initial begin
        #300000000;
        $display("FAIL: ROW0 LED test timed out");
        $finish;
    end

endmodule
