`timescale 1ns/1ps

module tb_pcm24_chorus;

    reg clk;
    reg rst_n;
    reg sample_valid_in;
    reg signed [23:0] pcm_in;
    reg chorus_enable;
    wire sample_valid;
    wire signed [23:0] pcm_out;
    wire [8:0] effect_blend;
    wire effect_busy;
    wire [7:0] lfo_position;

    pcm24_chorus #(
        .BUFFER_BITS(4), .BASE_DELAY(4), .MOD_DEPTH(2),
        .LFO_HOLD_SAMPLES(2), .BLEND_SAMPLES(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid_in(sample_valid_in),
        .pcm_in(pcm_in), .chorus_enable(chorus_enable),
        .sample_valid(sample_valid), .pcm_out(pcm_out),
        .effect_blend(effect_blend), .effect_busy(effect_busy),
        .lfo_position(lfo_position)
    );

    always #5 clk = ~clk;

    integer sample_index;
    integer changed_count;
    reg signed [23:0] stimulus;
    reg [8:0] previous_blend;

    task send_sample;
        input signed [23:0] value;
        begin
            @(negedge clk);
            pcm_in = value;
            sample_valid_in = 1'b1;
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b1) begin
                $display("FAIL: chorus sample_valid missing");
                $finish;
            end
            @(negedge clk);
            sample_valid_in = 1'b0;
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b0) begin
                $display("FAIL: chorus sample_valid did not clear");
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        pcm_in = 24'sd0;
        chorus_enable = 1'b0;
        changed_count = 0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Fill the delay while proving that disabled mode is bit-exact bypass.
        for (sample_index = 0; sample_index < 20;
             sample_index = sample_index + 1) begin
            stimulus = sample_index * 24'sd100003;
            send_sample(stimulus);
            if ((pcm_out !== stimulus) || (effect_blend !== 9'd0)) begin
                $display("FAIL: chorus bypass mismatch sample=%0d got=%0d expected=%0d",
                         sample_index, pcm_out, stimulus);
                $finish;
            end
        end

        chorus_enable = 1'b1;
        previous_blend = effect_blend;
        for (sample_index = 0; sample_index < 4;
             sample_index = sample_index + 1) begin
            stimulus = (sample_index[0]) ? -24'sd3000000 : 24'sd3000000;
            send_sample(stimulus);
            if (effect_blend !== previous_blend + 9'd64) begin
                $display("FAIL: chorus fade-up step got=%0d previous=%0d",
                         effect_blend, previous_blend);
                $finish;
            end
            previous_blend = effect_blend;
        end
        if (effect_busy || (effect_blend !== 9'd256)) begin
            $display("FAIL: chorus did not finish fade-up blend=%0d busy=%b",
                     effect_blend, effect_busy);
            $finish;
        end

        for (sample_index = 0; sample_index < 24;
             sample_index = sample_index + 1) begin
            stimulus = (sample_index[0]) ? -24'sd3000000 : 24'sd3000000;
            send_sample(stimulus);
            if (pcm_out !== stimulus)
                changed_count = changed_count + 1;
        end
        if ((changed_count < 12) || (lfo_position > 2)) begin
            $display("FAIL: chorus delay/LFO inactive changed=%0d lfo=%0d",
                     changed_count, lfo_position);
            $finish;
        end

        chorus_enable = 1'b0;
        previous_blend = effect_blend;
        for (sample_index = 0; sample_index < 4;
             sample_index = sample_index + 1) begin
            stimulus = sample_index * 24'sd170003;
            send_sample(stimulus);
            if (effect_blend !== previous_blend - 9'd64) begin
                $display("FAIL: chorus fade-down step got=%0d previous=%0d",
                         effect_blend, previous_blend);
                $finish;
            end
            previous_blend = effect_blend;
        end
        send_sample(-24'sd7654321);
        if ((effect_blend !== 9'd0) || effect_busy ||
            (pcm_out !== -24'sd7654321)) begin
            $display("FAIL: chorus did not return to exact bypass");
            $finish;
        end

        $display("PASS: PCM24 chorus short delay, triangle LFO and click-free bypass fade");
        $finish;
    end

endmodule
