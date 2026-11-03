`timescale 1ns/1ps

module tb_fret_note_event;

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
    wire [127:0] phase_inc;

    fret_note_event #(.VIBRATO_EXIT_INTERVAL(2)) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .stable_valid     (stable_valid),
        .stable_fret_id   (stable_fret_id),
        .pluck_valid      (pluck_valid),
        .sample_ce        (sample_ce),
        .note_on          (note_on),
        .note_off         (note_off),
        .slide_valid      (slide_valid),
        .vibrato_enable(),
        .voice_active     (voice_active),
        .current_fret_id  (current_fret_id),
        .phase_inc        (phase_inc)
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
        sample_ce       = 1'b0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Select string 0 fret 3 without plucking: no note event.
        pulse_stable(16'h0003);
        if ((note_on !== 4'b0000) || (note_off !== 4'b0000) ||
            (slide_valid !== 4'b0000) || (phase_inc[31:0] !== 32'h02173456)) begin
            $display("FAIL: fret selection");
            $finish;
        end

        // Plucking string 0 starts only that voice.
        pulse_pluck(4'b0001);
        if ((note_on !== 4'b0001) || (voice_active !== 4'b0001)) begin
            $display("FAIL: note_on event");
            $finish;
        end

        // Changing fret while active slides without restarting attack.
        pulse_stable(16'h0004);
        if ((note_on !== 4'b0000) || (note_off !== 4'b0000) ||
            (slide_valid !== 4'b0001) ||
            (phase_inc[31:0] !== 32'h02370783)) begin
            $display("FAIL: slide event");
            $finish;
        end

        // A final release is held briefly for a possible vibrato gesture.
        pulse_stable(16'h0000);
        if ((note_on !== 4'b0000) || (note_off !== 4'b0000) ||
            (slide_valid !== 4'b0000) || (voice_active !== 4'b0001) ||
            (phase_inc[31:0] !== 32'h02370783)) begin
            $display("FAIL: release candidate");
            $finish;
        end
        audio_sample;
        audio_sample;
        audio_sample;
        if ((note_off !== 4'b0001) || (voice_active !== 4'b0000)) begin
            $display("FAIL: delayed release event");
            $finish;
        end

        // A fresh open-string pluck must reset pitch even though no new stable
        // frame changed the fret after the delayed final release.
        pulse_pluck(4'b0001);
        if (note_on !== 4'b0001 || note_off !== 0 ||
            phase_inc[31:0] !== 32'h01c20d2f) begin
            $display("FAIL: fresh open-string pluck kept the old fretted pitch");
            $finish;
        end

        // A new fret after release selects a new pitch but does not pluck.
        pulse_stable(16'h0002);
        if ((note_on !== 4'b0000) || (note_off !== 4'b0000) ||
            (phase_inc[31:0] !== 32'h01F92A6D)) begin
            $display("FAIL: post-release pitch selection");
            $finish;
        end

        $display("PASS: stable fret to note events, slide and release");
        $finish;
    end

endmodule
