`timescale 1ns/1ps

module tb_xinxian_top;

    reg  sys_clk_50m;
    reg  rst_n;
    wire led;

    xinxian_top #(
        .CLK_HZ(10),
        .BLINK_HZ(1)
    ) dut (
        .sys_clk_50m(sys_clk_50m),
        .rst_n      (rst_n),
        .led        (led)
    );

    always #5 sys_clk_50m = ~sys_clk_50m;

    initial begin
        sys_clk_50m = 1'b0;
        rst_n       = 1'b0;

        repeat (3) @(posedge sys_clk_50m);
        #1;

        if (led !== 1'b0) begin
            $display("FAIL: LED reset state");
            $finish;
        end

        rst_n = 1'b1;

        repeat (2) @(posedge sys_clk_50m);
        #1;

        if (led !== 1'b0) begin
            $display("FAIL: LED changed during reset release");
            $finish;
        end

        repeat (5) @(posedge sys_clk_50m);
        #1;

        if (led !== 1'b1) begin
            $display("FAIL: LED did not toggle high");
            $finish;
        end

        repeat (5) @(posedge sys_clk_50m);
        #1;

        if (led !== 1'b0) begin
            $display("FAIL: LED did not toggle low");
            $finish;
        end

        $display("PASS: clock, reset and LED divider");
        $finish;
    end

endmodule