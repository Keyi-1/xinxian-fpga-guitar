`timescale 1ns/1ps

module tb_four_voice_audio_core;

    reg         clk;
    reg         rst_n;
    reg [3:0]   note_on;
    reg [3:0]   note_off;
    reg [127:0] phase_inc;

    wire        sample_tick;
    wire        sample_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0]  voice_active;
    wire signed [95:0] voice_pcm;

    four_voice_audio_core #(
        .SAMPLE_DIV(4)
    ) dut (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (sample_valid),
        .pcm_mix      (pcm_mix),
        .voice_active (voice_active),
        .voice_pcm    (voice_pcm)
    );

    always #5 clk = ~clk;

    task pulse_event;
        input [3:0] on_value;
        input [3:0] off_value;
        begin
            @(negedge clk);
            note_on  = on_value;
            note_off = off_value;
            @(negedge clk);
            note_on  = 4'd0;
            note_off = 4'd0;
        end
    endtask

    task wait_sample;
        integer guard;
        begin
            guard = 0;
            while (sample_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 1000) begin
                    $display("FAIL: audio sample timeout");
                    $finish;
                end
            end
            @(posedge clk);
            #1;
        end
    endtask

    integer k;
    reg found_nonzero;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        note_on = 4'd0;
        note_off = 4'd0;
        phase_inc = {
            32'h00C879A3,  // D3
            32'h010B9A2B,  // G3
            32'h0151285D,  // B3
            32'h01C20D2F   // E4
        };

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // A one-clock event must be retained until the audio tick.
        pulse_event(4'b0001, 4'b0000);
        wait_sample;
        if (voice_active !== 4'b0001) begin
            $display("FAIL: retained single-string note_on");
            $finish;
        end

        found_nonzero = 1'b0;
        for (k = 0; k < 40; k = k + 1) begin
            wait_sample;
            if (pcm_mix !== 24'sd0)
                found_nonzero = 1'b1;
        end
        if (!found_nonzero) begin
            $display("FAIL: single voice produced no PCM");
            $finish;
        end

        // Add string 2 without disturbing string 0.
        pulse_event(4'b0100, 4'b0000);
        wait_sample;
        if (voice_active !== 4'b0101) begin
            $display("FAIL: independent second voice");
            $finish;
        end

        // Stop string 0 only. It enters Release and therefore remains
        // active temporarily; string 2 must remain active as well.
        pulse_event(4'b0000, 4'b0001);
        wait_sample;
        if (voice_active !== 4'b0101) begin
            $display("FAIL: independent note_off");
            $finish;
        end

        $display("PASS: four-voice audio core, event hold and independent voices");
        $finish;
    end

endmodule
