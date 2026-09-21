`timescale 1ns/1ps

module tb_four_string_vibrato_gesture;
    reg clk;
    reg rst_n;
    reg stable_valid;
    reg [15:0] stable_fret_id;
    reg [3:0] pluck_valid;
    reg sample_ce;
    wire [3:0] note_on;
    wire [3:0] note_off;
    wire [3:0] slide_valid;
    wire [3:0] voice_active;
    wire [127:0] target_phase_inc;
    wire [127:0] phase_inc;
    wire [3:0] slide_busy;
    wire [3:0] vibrato_enable;

    four_string_voice_control #(
        .SLIDE_SAMPLES(4), .VIBRATO_TAP_COUNT(3),
        .VIBRATO_MIN_INTERVAL(2), .VIBRATO_MAX_INTERVAL(6),
        .VIBRATO_EXIT_INTERVAL(8), .VIBRATO_WINDOW(24),
        .VIBRATO_LFO_PHASE_INC(32'h20000000), .VIBRATO_DEPTH_Q15(16'd1024)
    ) dut (
        .clk(clk), .rst_n(rst_n), .stable_valid(stable_valid),
        .stable_fret_id(stable_fret_id), .pluck_valid(pluck_valid),
        .sample_ce(sample_ce), .note_on(note_on), .note_off(note_off),
        .slide_valid(slide_valid), .voice_active(voice_active),
        .current_fret_id(), .target_phase_inc(target_phase_inc),
        .phase_inc(phase_inc), .slide_busy(slide_busy),
        .vibrato_enable(vibrato_enable)
    );

    always #5 clk = ~clk;

    task stable_fret;
        input [15:0] value;
        begin
            @(negedge clk); stable_fret_id = value; stable_valid = 1'b1;
            @(negedge clk); stable_valid = 1'b0; #1;
        end
    endtask

    task pluck;
        begin
            @(negedge clk); pluck_valid = 4'b0001;
            @(negedge clk); pluck_valid = 4'd0; #1;
        end
    endtask

    task audio_sample;
        begin
            @(negedge clk); sample_ce = 1'b1;
            @(negedge clk); sample_ce = 1'b0; #1;
        end
    endtask

    task valid_tap;
        begin
            stable_fret(16'h0000);
            audio_sample;
            audio_sample;
            stable_fret(16'h0003);
        end
    endtask

    integer k;
    reg [31:0] base_phase;
    reg saw_above;
    reg saw_below;
    reg [95:0] other_phase_before;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        stable_valid = 1'b0;
        stable_fret_id = 16'd0;
        pluck_valid = 4'd0;
        sample_ce = 1'b0;
        saw_above = 1'b0;
        saw_below = 1'b0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        stable_fret(16'h0003);
        pluck();
        audio_sample;
        if ((note_on !== 4'd0) || (voice_active !== 4'b0001)) begin
            $display("FAIL: vibrato test note did not start");
            $finish;
        end

        base_phase = target_phase_inc[31:0];
        other_phase_before = phase_inc[127:32];

        // One valid tap is not enough to enter vibrato.
        valid_tap();
        if ((vibrato_enable !== 4'd0) || (note_on !== 4'd0) ||
            (note_off !== 4'd0) || (slide_valid !== 4'd0)) begin
            $display("FAIL: one same-fret tap entered or retriggered vibrato");
            $finish;
        end

        valid_tap();
        valid_tap();
        if ((vibrato_enable !== 4'b0001) || (voice_active !== 4'b0001) ||
            (note_on !== 4'd0) || (note_off !== 4'd0) ||
            (slide_valid !== 4'd0)) begin
            $display("FAIL: three same-fret taps did not enter clean vibrato");
            $finish;
        end

        for (k = 0; k < 8; k = k + 1) begin
            audio_sample;
            if (phase_inc[31:0] > base_phase) saw_above = 1'b1;
            if (phase_inc[31:0] < base_phase) saw_below = 1'b1;
            if (phase_inc[127:32] !== other_phase_before) begin
                $display("FAIL: vibrato affected another string");
                $finish;
            end
        end
        if (!saw_above || !saw_below) begin
            $display("FAIL: LFO did not modulate around base pitch");
            $finish;
        end

        // A different fret is an ordinary slide and exits vibrato.
        stable_fret(16'h0004);
        if ((vibrato_enable !== 4'd0) || (slide_valid !== 4'b0001) ||
            (note_on !== 4'd0) || (note_off !== 4'd0)) begin
            $display("FAIL: different fret did not exit to ordinary slide");
            $finish;
        end

        $display("PASS: three-tap same-fret vibrato gesture, LFO, isolation and slide exit");
        $finish;
    end
endmodule
