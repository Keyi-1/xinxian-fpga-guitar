`timescale 1ns/1ps

module tb_phase_slide_smoother;

    reg        clk;
    reg        rst_n;
    reg        sample_ce;
    reg        note_on;
    reg        voice_active;
    reg [31:0] target_phase_inc;

    wire [31:0] phase_inc;
    wire        busy;

    phase_slide_smoother #(
        .SLIDE_SAMPLES(4)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_ce      (sample_ce),
        .note_on         (note_on),
        .voice_active    (voice_active),
        .target_phase_inc(target_phase_inc),
        .phase_inc       (phase_inc),
        .busy            (busy)
    );

    always #5 clk = ~clk;

    task audio_sample;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            @(negedge clk);
            sample_ce = 1'b0;
            #1;
        end
    endtask

    task check_phase;
        input [31:0] expected_phase;
        input        expected_busy;
        begin
            if ((phase_inc !== expected_phase) || (busy !== expected_busy)) begin
                $display("FAIL: phase=%0d/%0d busy=%b/%b",
                         phase_inc, expected_phase, busy, expected_busy);
                $finish;
            end
        end
    endtask

    initial begin
        clk             = 1'b0;
        rst_n           = 1'b0;
        sample_ce       = 1'b0;
        note_on         = 1'b0;
        voice_active    = 1'b0;
        target_phase_inc= 32'd1000;

        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;

        // Inactive voice selects a new target immediately.
        audio_sample;
        check_phase(32'd1000, 1'b0);

        // A pluck also applies its target immediately.
        voice_active = 1'b1;
        note_on      = 1'b1;
        audio_sample;
        note_on      = 1'b0;
        check_phase(32'd1000, 1'b0);

        // Upward slide: 1000 -> 2000 in four sample enables.
        target_phase_inc = 32'd2000;
        audio_sample; check_phase(32'd1250, 1'b1);
        audio_sample; check_phase(32'd1500, 1'b1);
        audio_sample; check_phase(32'd1750, 1'b1);
        audio_sample; check_phase(32'd2000, 1'b0);

        // Downward slide also remains monotonic and reaches the target.
        target_phase_inc = 32'd500;
        audio_sample; check_phase(32'd1625, 1'b1);
        audio_sample; check_phase(32'd1250, 1'b1);
        audio_sample; check_phase(32'd875, 1'b1);
        audio_sample; check_phase(32'd500, 1'b0);

        // If the voice is inactive, a target change does not glide.
        voice_active     = 1'b0;
        target_phase_inc = 32'd3000;
        audio_sample;
        check_phase(32'd3000, 1'b0);

        $display("PASS: phase increment slide smoothing and immediate retrigger");
        $finish;
    end

endmodule
