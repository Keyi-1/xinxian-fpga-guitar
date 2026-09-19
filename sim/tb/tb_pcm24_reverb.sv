`timescale 1ns/1ps

module tb_pcm24_reverb;

    reg clk;
    reg rst_n;
    reg sample_valid_in;
    reg signed [23:0] pcm_in;
    reg reverb_enable;
    wire sample_valid;
    wire signed [23:0] pcm_out;
    wire [8:0] effect_blend;
    wire effect_busy;

    pcm24_reverb #(
        .DELAY_A(3), .DELAY_B(5), .DELAY_C(7), .BLEND_SAMPLES(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid_in(sample_valid_in),
        .pcm_in(pcm_in), .reverb_enable(reverb_enable),
        .sample_valid(sample_valid), .pcm_out(pcm_out),
        .effect_blend(effect_blend), .effect_busy(effect_busy)
    );

    always #5 clk = ~clk;

    integer k;
    integer echo_count;
    integer late_nonzero_count;
    integer magnitude;
    integer maximum_magnitude;
    reg [8:0] previous_blend;

    function integer abs24;
        input signed [23:0] value;
        begin
            if (value < 0) abs24 = -value;
            else abs24 = value;
        end
    endfunction

    task send_sample;
        input signed [23:0] value;
        begin
            @(negedge clk);
            pcm_in = value;
            sample_valid_in = 1'b1;
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b1) begin
                $display("FAIL: reverb sample_valid missing");
                $finish;
            end
            @(negedge clk);
            sample_valid_in = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        pcm_in = 24'sd0;
        reverb_enable = 1'b0;
        echo_count = 0;
        late_nonzero_count = 0;
        maximum_magnitude = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Disabled mode must be an exact dry bypass while delay RAM fills.
        for (k = 0; k < 12; k = k + 1) begin
            send_sample(k * 24'sd12345);
            if ((pcm_out !== k * 24'sd12345) || (effect_blend !== 0)) begin
                $display("FAIL: reverb bypass mismatch k=%0d got=%0d", k, pcm_out);
                $finish;
            end
        end

        reverb_enable = 1'b1;
        previous_blend = effect_blend;
        for (k = 0; k < 4; k = k + 1) begin
            send_sample(24'sd0);
            if (effect_blend !== previous_blend + 9'd64) begin
                $display("FAIL: reverb fade-up step got=%0d previous=%0d",
                         effect_blend, previous_blend);
                $finish;
            end
            previous_blend = effect_blend;
        end
        if (effect_busy || (effect_blend !== 9'd256)) begin
            $display("FAIL: reverb fade-up incomplete");
            $finish;
        end

        send_sample(24'sd4000000);
        for (k = 0; k < 160; k = k + 1) begin
            send_sample(24'sd0);
            magnitude = abs24(pcm_out);
            if (magnitude != 0)
                echo_count = echo_count + 1;
            if (magnitude > maximum_magnitude)
                maximum_magnitude = magnitude;
            if ((k >= 140) && (magnitude != 0))
                late_nonzero_count = late_nonzero_count + 1;
            if (magnitude > 4000000) begin
                $display("FAIL: reverb feedback grew magnitude=%0d k=%0d",
                         magnitude, k);
                $finish;
            end
        end
        if ((echo_count < 8) || (late_nonzero_count != 0)) begin
            $display("FAIL: reverb tail invalid echoes=%0d late=%0d max=%0d",
                     echo_count, late_nonzero_count, maximum_magnitude);
            $finish;
        end

        reverb_enable = 1'b0;
        previous_blend = effect_blend;
        for (k = 0; k < 4; k = k + 1) begin
            send_sample(24'sd0);
            if (effect_blend !== previous_blend - 9'd64) begin
                $display("FAIL: reverb fade-down step got=%0d previous=%0d",
                         effect_blend, previous_blend);
                $finish;
            end
            previous_blend = effect_blend;
        end
        send_sample(-24'sd7654321);
        if ((pcm_out !== -24'sd7654321) || effect_busy ||
            (effect_blend !== 0)) begin
            $display("FAIL: reverb did not return to exact bypass");
            $finish;
        end

        $display("PASS: bounded three-tap PCM24 feedback reverb, tail and bypass fade");
        $finish;
    end

endmodule
