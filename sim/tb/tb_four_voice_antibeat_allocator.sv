`timescale 1ns/1ps
module tb_four_voice_antibeat_allocator;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [3:0] on = 0, active = 0;
    reg [127:0] phase = 0;
    reg [31:0] notes [0:35];
    wire [3:0] pan, legacy_pan;
    wire [35:0] gain, legacy_gain;
    four_voice_antibeat_allocator dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(1'b1),
        .note_on(on), .voice_active(active),
        .selected_phase_inc(phase), .audible_phase_inc(phase),
        .pan_right(pan), .gain_q8(gain)
    );
    four_voice_antibeat_allocator #(.ENABLE(0)) baseline (
        .clk(clk), .rst_n(rst_n), .sample_tick(1'b1),
        .note_on(on), .voice_active(active),
        .selected_phase_inc(phase), .audible_phase_inc(phase),
        .pan_right(legacy_pan), .gain_q8(legacy_gain)
    );
    task reset_case;
        begin
            @(negedge clk); rst_n = 0; on = 0; active = 0;
            repeat (4) @(negedge clk); rst_n = 1;
        end
    endtask
    task start_voice(input integer s);
        begin
            @(negedge clk); on = 1 << s;
            @(negedge clk); on = 0; active[s] = 1;
            repeat (2) @(negedge clk);
        end
    endtask
    integer i, j, t;
    reg [35:0] previous_gain;
    initial begin
        $readmemh("../../mem/note_phase_inc.mem",notes);
        phase = {notes[35],notes[26],notes[14],notes[2]}; // A#3/D#4/E4/F#4
        reset_case();
        start_voice(0); start_voice(1); start_voice(2);
        if (pan[0] == pan[1] || pan[2] != pan[0] || legacy_pan[2] != legacy_pan[1])
            $fatal(1, "FAIL: close E4/D#4 allocation pan=%b legacy=%b phase=%h",
                   pan,legacy_pan,phase);
        previous_gain = gain;
        for (t = 0; t < 100; t = t + 1) begin
            @(negedge clk);
            for (i = 0; i < 4; i = i + 1)
                if ($signed({1'b0,gain[i*9 +: 9]}) -
                    $signed({1'b0,previous_gain[i*9 +: 9]}) > 2 ||
                    $signed({1'b0,previous_gain[i*9 +: 9]}) -
                    $signed({1'b0,gain[i*9 +: 9]}) > 2)
                    $fatal(1, "FAIL: pair gain jumps");
            previous_gain = gain;
        end
        if (gain[8:0] != 128 || gain[17:9] != 256 || gain[26:18] != 256 ||
            legacy_gain != {4{9'd256}})
            $fatal(1, "FAIL: only older close-pair voice is attenuated");
        start_voice(3);
        if ($countones(pan) != 2) $fatal(1, "FAIL: four voices must balance 2+2");
        start_voice(0); // Repluck becomes the newest in that close pair.
        repeat (100) @(negedge clk);
        if (pan != 4'b1010 || gain[8:0] != 256 || gain[26:18] != 128)
            $fatal(1, "FAIL: reattack priority/pan retention");
        phase[95:64] = phase[31:0]; // Exact unison is not beating.
        repeat (100) @(negedge clk);
        if (gain != {4{9'd256}}) $fatal(1, "FAIL: unison gain restoration");
        active[2] = 0;
        repeat (100) @(negedge clk);
        if (gain != {4{9'd256}}) $fatal(1, "FAIL: quiet partner gain restoration");
        for (i = 0; i < 4; i = i + 1)
            for (j = i+1; j < 4; j = j + 1) begin
                reset_case(); start_voice(i); start_voice(j);
                if (pan[i] == pan[j] || gain != {4{9'd256}})
                    $fatal(1, "FAIL: first two voices must remain hard stereo/full gain");
            end
        $display("PASS: pitch-aware third voice, six first pairs, smooth -6 dB close-pair weighting, reattack/unison/release");
        $finish;
    end
endmodule
