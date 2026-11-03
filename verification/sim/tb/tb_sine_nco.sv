`timescale 1ns/1ps

module tb_sine_nco;

    reg        clk;
    reg        rst_n;
    reg        sample_ce;
    reg [31:0] phase_inc;

    wire signed [15:0] sample_out;
    wire               sample_valid;

    sine_nco dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_ce   (sample_ce),
        .phase_inc   (phase_inc),
        .sample_out  (sample_out),
        .sample_valid(sample_valid)
    );

    always #5 clk = ~clk;

    task sample_once;
        begin
            sample_ce = 1'b1;
            @(posedge clk);
            #1;
            sample_ce = 1'b0;
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        sample_ce = 1'b0;

        // 每个采样推进 1/16 周期
        phase_inc = 32'h10000000;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        sample_once;
        if (sample_valid !== 1'b1 || sample_out <= 0) begin
            $display("FAIL: first quadrant sample");
            $finish;
        end

        sample_once;
        if (sample_out <= 0) begin
            $display("FAIL: positive sine quadrant");
            $finish;
        end

        repeat (6) sample_once;

        // 第 8/16 周期应接近过零
        if (sample_out > 16'sd1024 ||
            sample_out < -16'sd1024) begin
            $display("FAIL: zero crossing, value=%0d", sample_out);
            $finish;
        end

        sample_once;

        if (sample_out >= 0) begin
            $display("FAIL: negative sine quadrant");
            $finish;
        end

        $display("PASS: sine NCO phase and sign");
        $finish;
    end

endmodule