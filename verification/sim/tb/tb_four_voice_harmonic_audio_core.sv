`timescale 1ns/1ps

module tb_four_voice_harmonic_audio_core;

    reg clk;
    reg rst_n;
    reg [3:0] note_on;
    reg [3:0] note_off;
    reg [7:0] velocity_level;
    reg [127:0] phase_inc;

    wire sample_tick;
    wire sample_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0] voice_active;
    wire signed [95:0] voice_pcm;
    wire [3:0] voice_busy;
    wire [3:0] deadline_miss;

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(64),
        .HARMONICS(32)
    ) dut (
        .clk_audio_ref(clk), .rst_n(rst_n),
        .note_on(note_on), .note_off(note_off),
        .velocity_level(velocity_level), .phase_inc(phase_inc),
        .timbre_select(1'b0),
        .sustain_enable(1'b0),
        .sample_tick(sample_tick), .sample_valid(sample_valid),
        .pcm_mix(pcm_mix), .voice_active(voice_active),
        .voice_pcm(voice_pcm), .voice_busy(voice_busy),
        .deadline_miss(deadline_miss), .timbre_blend(), .timbre_busy()
    );

    always #5 clk = ~clk;

    task pulse_event;
        input [3:0] on_value;
        input [3:0] off_value;
        begin
            @(negedge clk);
            note_on = on_value;
            note_off = off_value;
            @(negedge clk);
            note_on = 4'd0;
            note_off = 4'd0;
        end
    endtask

    function signed [23:0] expected_mix;
        input signed [23:0] a;
        input signed [23:0] b;
        input signed [23:0] c;
        input signed [23:0] d;
        reg signed [25:0] sum;
        begin
            sum = $signed({{2{a[23]}}, a}) + $signed({{2{b[23]}}, b}) +
                  $signed({{2{c[23]}}, c}) + $signed({{2{d[23]}}, d});
            if (sum > 26'sd8388607)
                expected_mix = 24'sh7fffff;
            else if (sum < -26'sd8388608)
                expected_mix = 24'sh800000;
            else
                expected_mix = sum[23:0];
        end
    endfunction

    integer result_count;
    integer nonzero_count;
    integer guard;
    reg signed [23:0] expected_pcm;

    always @(posedge clk) begin
        if (rst_n && (dut.sample_valid0 || dut.sample_valid1 ||
                      dut.sample_valid2 || dut.sample_valid3)) begin
            if ({dut.sample_valid3, dut.sample_valid2,
                 dut.sample_valid1, dut.sample_valid0} !== 4'b1111) begin
                $display("FAIL: harmonic voice results were not synchronous");
                $finish;
            end
        end
    end

    task wait_mixed_sample;
        begin
            guard = 0;
            while (sample_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 300) begin
                    $display("FAIL: harmonic mixed sample timeout");
                    $finish;
                end
            end
            #1;
            expected_pcm = expected_mix(voice_pcm[23:0], voice_pcm[47:24],
                                        voice_pcm[71:48], voice_pcm[95:72]);
            if (pcm_mix !== expected_pcm) begin
                $display("FAIL: harmonic mixer got %0d expected %0d", pcm_mix,
                         expected_pcm);
                $finish;
            end
            result_count = result_count + 1;
            if (pcm_mix != 24'sd0)
                nonzero_count = nonzero_count + 1;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        note_on = 4'd0;
        note_off = 4'd0;
        velocity_level = 8'hE4;
        phase_inc = {32'h00C879A3, 32'h010B9A2B, 32'h0151285D, 32'h01C20D2F};
        result_count = 0;
        nonzero_count = 0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        // One-clock events must reach the common upcoming sample boundary.
        pulse_event(4'b1111, 4'b0000);
        wait_mixed_sample;
        if (voice_active !== 4'b1111) begin
            $display("FAIL: four harmonic voices did not start together");
            $finish;
        end

        repeat (7) wait_mixed_sample;
        if (nonzero_count < 4) begin
            $display("FAIL: four harmonic voices produced insufficient PCM");
            $finish;
        end
        if (deadline_miss !== 4'd0 || voice_busy !== 4'd0) begin
            $display("FAIL: harmonic schedule deadline_miss=%b busy=%b",
                     deadline_miss, voice_busy);
            $finish;
        end

        // Release only voice 1. The other voices must remain active.
        pulse_event(4'b0000, 4'b0010);
        wait_mixed_sample;
        if (voice_active !== 4'b1111) begin
            $display("FAIL: one harmonic release disturbed another voice");
            $finish;
        end

        $display("PASS: four-voice harmonic PCM core, synchronous mix and deadlines");
        $finish;
    end

endmodule
