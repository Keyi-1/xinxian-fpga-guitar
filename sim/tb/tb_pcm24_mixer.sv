`timescale 1ns/1ps

module tb_pcm24_mixer;

    reg clk;
    reg rst_n;
    reg sample_valid_in;
    reg signed [23:0] pcm0;
    reg signed [23:0] pcm1;
    reg signed [23:0] pcm2;
    reg signed [23:0] pcm3;

    wire sample_valid;
    wire signed [23:0] pcm_out;

    pcm24_mixer dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_valid_in (sample_valid_in),
        .pcm0            (pcm0),
        .pcm1            (pcm1),
        .pcm2            (pcm2),
        .pcm3            (pcm3),
        .sample_valid    (sample_valid),
        .pcm_out         (pcm_out)
    );

    always #5 clk = ~clk;

    task submit;
        input signed [23:0] a;
        input signed [23:0] b;
        input signed [23:0] c;
        input signed [23:0] d;
        begin
            @(negedge clk);
            pcm0 = a; pcm1 = b; pcm2 = c; pcm3 = d;
            sample_valid_in = 1'b1;
            @(negedge clk);
            sample_valid_in = 1'b0;
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        pcm0 = 0; pcm1 = 0; pcm2 = 0; pcm3 = 0;

        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;

        submit(24'sd100, 24'sd200, -24'sd50, 24'sd25);
        if ((sample_valid !== 1'b1) || (pcm_out !== 24'sd275)) begin
            $display("FAIL: normal PCM24 mix");
            $finish;
        end

        submit(24'sh7fffff, 24'sd1, 24'sd0, 24'sd0);
        if (pcm_out !== 24'sh7fffff) begin
            $display("FAIL: positive PCM24 saturation");
            $finish;
        end

        submit(-24'sh800000, -24'sd1, 24'sd0, 24'sd0);
        if (pcm_out !== 24'sh800000) begin
            $display("FAIL: negative PCM24 saturation");
            $finish;
        end

        $display("PASS: four-voice PCM24 mix and saturation");
        $finish;
    end

endmodule
