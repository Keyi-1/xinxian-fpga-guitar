`timescale 1ns/1ps
// An excitation of either channel must not enter the other delay/effect state.
module tb_stereo_audio_effects;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, valid_in = 0;
    reg signed [23:0] left_in = 0, right_in = 0;
    wire valid;
    wire signed [23:0] left_out, right_out;
    wire [8:0] cb, rb;
    stereo_audio_effects #(.ENABLE(1)) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid_in(valid_in),
        .pcm_left(left_in), .pcm_right(right_in), .drive_level(2'd3),
        .timbre_blend(9'd256), .chorus_enable(1'b1), .reverb_enable(1'b1),
        .sample_valid(valid), .left_out(left_out), .right_out(right_out),
        .chorus_blend(cb), .reverb_blend(rb), .chorus_busy(), .reverb_busy()
    );
    integer selected_side = 0, output_count = 0, tail_count = 0;
    integer last_output = 0, cycles = 0, sent = 0;
    always @(posedge clk) begin
        cycles = cycles + 1;
        #1;
        if (rst_n && valid) begin
            if (last_output != 0 && cycles-last_output != 256)
                $fatal(1, "FAIL: stereo effect sample cadence");
            last_output = cycles;
            output_count = output_count + 1;
            if ((selected_side == 0 && right_out !== 0) ||
                (selected_side == 1 && left_out !== 0))
                $fatal(1, "FAIL: stereo effect crossfeed");
            if (sent > 1000 && (left_out != 0 || right_out != 0))
                tail_count = tail_count + 1;
            if (dut.g_effects.valid[0] !== dut.g_effects.valid[1])
                $fatal(1, "FAIL: stereo effect channel timing differs");
        end
    end
    integer side, frame;
    initial begin
        for (side = 0; side < 2; side = side + 1) begin
            @(negedge clk); rst_n = 0; valid_in = 0; left_in = 0; right_in = 0;
            selected_side = side; output_count = 0; tail_count = 0; last_output = 0;
            repeat (8) @(negedge clk);
            rst_n = 1;
            for (frame = 0; frame < 4000; frame = frame + 1) begin
                sent = frame;
                @(negedge clk);
                valid_in = 1;
                left_in = (side == 0 && frame >= 300 && frame < 400) ? 24'sd1000000 : 0;
                right_in = (side == 1 && frame >= 300 && frame < 400) ? 24'sd1000000 : 0;
                @(negedge clk); valid_in = 0;
                repeat (254) @(negedge clk);
            end
            if (output_count != 4000 || tail_count == 0 || cb != 256 || rb != 256)
                $fatal(1, "FAIL: effect cadence, delay tail or switch settling");
        end
        $display("PASS: both stereo effect channels preserve cadence and isolated chorus/reverb tails");
        $finish;
    end
    initial begin #25000000; $fatal(1, "FAIL: stereo effect timeout"); end
endmodule
