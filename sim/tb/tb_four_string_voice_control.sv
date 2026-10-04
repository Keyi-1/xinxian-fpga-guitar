`timescale 1ns/1ps

module tb_four_string_voice_control;

    reg         clk;
    reg         rst_n;
    reg         stable_valid;
    reg [15:0]  stable_fret_id;
    reg [3:0]   pluck_valid;
    reg         sample_ce;

    wire [3:0]   note_on;
    wire [3:0]   note_off;
    wire [3:0]   slide_valid;
    wire [3:0]   voice_active;
    wire [15:0]  current_fret_id;
    wire [127:0] target_phase_inc;
    wire [127:0] phase_inc;
    wire [3:0]   slide_busy;

    four_string_voice_control #(
        .SLIDE_SAMPLES(4), .VIBRATO_EXIT_INTERVAL(0)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .stable_valid    (stable_valid),
        .stable_fret_id  (stable_fret_id),
        .pluck_valid     (pluck_valid),
        .sample_ce       (sample_ce),
        .note_on         (note_on),
        .note_off        (note_off),
        .slide_valid     (slide_valid),
        .vibrato_enable(),
        .voice_active    (voice_active),
        .current_fret_id (current_fret_id),
        .target_phase_inc(target_phase_inc),
        .phase_inc       (phase_inc),
        .slide_busy      (slide_busy)
    );

    always #5 clk = ~clk;

    task pulse_stable;
        input [15:0] fret_id_value;
        begin
            @(negedge clk);
            stable_fret_id = fret_id_value;
            stable_valid   = 1'b1;
            @(negedge clk);
            stable_valid   = 1'b0;
            #1;
        end
    endtask

    task pulse_pluck;
        input [3:0] pluck_value;
        begin
            @(negedge clk);
            pluck_valid = pluck_value;
            @(negedge clk);
            pluck_valid = 4'd0;
            #1;
        end
    endtask

    task audio_sample;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            @(negedge clk);
            sample_ce = 1'b0;
            #1;
        end
    endtask

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        stable_valid   = 1'b0;
        stable_fret_id = 16'h0000;
        pluck_valid    = 4'd0;
        sample_ce      = 1'b0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // String 0 selects E4 fret 3; string 1 remains open B3.
        pulse_stable(16'h0003);
        audio_sample;
        if ((target_phase_inc[31:0] !== 32'h02173456) ||
            (phase_inc[31:0] !== 32'h02173456) ||
            (note_on !== 4'b0000) ||
            (voice_active !== 4'b0000)) begin
            $display("FAIL: four-string pitch selection");
            $finish;
        end

        // Pluck strings 0 and 2 independently.
        pulse_pluck(4'b0101);
        if ((note_on !== 4'b0101) || (voice_active !== 4'b0101)) begin
            $display("FAIL: independent multi-string pluck");
            $finish;
        end
        audio_sample;

        // Change only string 0 from fret 3 to fret 4. String 2 must not
        // report a slide or become busy.
        pulse_stable(16'h0004);
        if ((slide_valid !== 4'b0001) ||
            (target_phase_inc[31:0] !== 32'h02370783) ||
            (slide_valid[2] !== 1'b0)) begin
            $display("FAIL: four-string slide target");
            $finish;
        end

        audio_sample;
        if ((phase_inc[31:0] !== 32'h021F2922) ||
            (slide_busy !== 4'b0001) ||
            (phase_inc[95:64] !== 32'h010B9A2B)) begin
            $display("FAIL: independent slide progress");
            $finish;
        end

        // Complete the remaining three steps.
        audio_sample;
        audio_sample;
        audio_sample;
        if ((phase_inc[31:0] !== 32'h02370783) ||
            (slide_busy[0] !== 1'b0) ||
            (phase_inc[95:64] !== 32'h010B9A2B)) begin
            $display("FAIL: slide completion");
            $finish;
        end

        // Releasing string 0 produces note_off only for string 0 and holds
        // its previous phase target.
        pulse_stable(16'h0000);
        if ((note_off !== 4'b0001) ||
            (voice_active !== 4'b0100) ||
            (target_phase_inc[31:0] !== 32'h02370783)) begin
            $display("FAIL: independent release");
            $finish;
        end

        $display("PASS: four-string event control and independent slide smoothing");
        $finish;
    end

endmodule
