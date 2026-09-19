`timescale 1ns/1ps

module tb_pcm24_rock_soft_clip;

    reg clk;
    reg rst_n;
    reg sample_valid_in;
    reg signed [23:0] pcm_in;
    reg [1:0] drive_level;
    reg [8:0] timbre_blend;
    wire sample_valid;
    wire signed [23:0] pcm_out;

    pcm24_rock_soft_clip dut (
        .clk(clk), .rst_n(rst_n), .sample_valid_in(sample_valid_in),
        .pcm_in(pcm_in), .drive_level(drive_level),
        .timbre_blend(timbre_blend), .sample_valid(sample_valid),
        .pcm_out(pcm_out)
    );

    always #5 clk = ~clk;

    task check_sample;
        input signed [23:0] stimulus;
        input [1:0] drive;
        input [8:0] blend;
        input signed [23:0] expected;
        begin
            @(negedge clk);
            pcm_in = stimulus;
            drive_level = drive;
            timbre_blend = blend;
            sample_valid_in = 1'b1;
            @(posedge clk);
            #1;
            if ((sample_valid !== 1'b1) || (pcm_out !== expected)) begin
                $display("FAIL: soft clip in=%0d drive=%0d blend=%0d got=%0d expected=%0d valid=%b",
                         stimulus, drive, blend, pcm_out, expected, sample_valid);
                $finish;
            end
            @(negedge clk);
            sample_valid_in = 1'b0;
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b0) begin
                $display("FAIL: soft clip sample_valid did not clear");
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        pcm_in = 24'sd0;
        drive_level = 2'd0;
        timbre_blend = 9'd0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Classic is an exact bypass even with maximum drive selected.
        check_sample(24'sh7fffff, 2'd3, 9'd0, 24'sh7fffff);
        check_sample(24'sh800000, 2'd3, 9'd0, 24'sh800000);

        // Fully-rock low-level signal remains linear at unity drive.
        check_sample(24'sd1000000, 2'd0, 9'd256, 24'sd1000000);

        // 3,000,000 * 2 enters the knee: 4,194,304 + (1,805,696 / 2).
        check_sample(24'sd3000000, 2'd3, 9'd256, 24'sd5097152);
        check_sample(-24'sd3000000, 2'd3, 9'd256, -24'sd5097152);

        // Extreme positive and negative values saturate without wraparound.
        check_sample(24'sh7fffff, 2'd3, 9'd256, 24'sh7fffff);
        check_sample(24'sh800000, 2'd3, 9'd256, 24'sh800000);

        // Half blend is the arithmetic mean of dry and fully wet.
        check_sample(24'sd3000000, 2'd3, 9'd128, 24'sd4048576);

        $display("PASS: velocity-controlled PCM24 rock soft clip, bypass, blend and saturation");
        $finish;
    end

endmodule
