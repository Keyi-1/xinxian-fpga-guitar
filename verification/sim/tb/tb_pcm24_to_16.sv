`timescale 1ns/1ps

module tb_pcm24_to_16;

    reg clk;
    reg rst_n;
    reg pcm_valid;
    reg signed [23:0] pcm_in;

    wire sample_valid;
    wire signed [15:0] sample_out;

    pcm24_to_16 dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .pcm_valid   (pcm_valid),
        .pcm_in      (pcm_in),
        .sample_valid(sample_valid),
        .sample_out  (sample_out)
    );

    always #5 clk = ~clk;

    task check_sample;
        input signed [23:0] input_value;
        input signed [15:0] expected_value;
        begin
            pcm_in    = input_value;
            pcm_valid = 1'b1;

            @(posedge clk);
            #1;

            if (sample_valid !== 1'b1 ||
                sample_out !== expected_value) begin
                $display(
                    "FAIL: input=%0d output=%0d expected=%0d",
                    input_value,
                    sample_out,
                    expected_value
                );
                $finish;
            end

            pcm_valid = 1'b0;

            @(posedge clk);
            #1;

            if (sample_valid !== 1'b0) begin
                $display("FAIL: sample_valid did not return low");
                $finish;
            end
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        pcm_valid = 1'b0;
        pcm_in    = 24'sd0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // 0 → 0
        check_sample(24'sd0, 16'sd0);

        // 0x00123400 / 256 = 0x1234
        check_sample(24'sd1192960, 16'sd4660);

        // 负数对称舍入
        check_sample(-24'sd1192960, -16'sd4660);

        // 正向饱和
        check_sample(24'sh7fffff, 16'sh7fff);

        // 负向饱和
        check_sample(-24'sd8388608, 16'sh8000);

        $display("PASS: 24-bit to 16-bit rounding and saturation");
        $finish;
    end

endmodule