`timescale 1ns/1ps

// Verifies a click-resistant runtime switch between the classic and rock
// 32-harmonic profiles.  A classic-only reference proves that timbre changes
// do not alter note lifecycle, phase scheduling or envelope state.
module tb_harmonic_timbre_switch;

    localparam [2:0] STATE_ATTACK = 3'd1;

    reg clk;
    reg rst_n;
    reg [3:0] note_on;
    reg [3:0] note_off;
    reg timbre_select;

    wire dut_sample_valid;
    wire ref_sample_valid;
    wire signed [23:0] dut_pcm_mix;
    wire signed [23:0] ref_pcm_mix;
    wire [3:0] dut_voice_active;
    wire [3:0] ref_voice_active;
    wire signed [95:0] dut_voice_pcm;
    wire signed [95:0] ref_voice_pcm;
    wire [3:0] dut_voice_busy;
    wire [3:0] ref_voice_busy;
    wire [3:0] dut_deadline_miss;
    wire [3:0] ref_deadline_miss;
    wire [8:0] timbre_blend;
    wire timbre_busy;

    wire [127:0] phase_inc = {
        32'h00C879A3, 32'h010B9A2B, 32'h0151285D, 32'h01C20D2F
    };

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(64),
        .HARMONICS(32),
        .TIMBRE_BLEND_SAMPLES(256)
    ) u_dut (
        .clk_audio_ref(clk), .rst_n(rst_n),
        .note_on(note_on), .note_off(note_off),
        .velocity_level(8'hff), .phase_inc(phase_inc),
        .timbre_select(timbre_select),
        .sustain_enable(1'b0),
        .sample_tick(), .sample_valid(dut_sample_valid),
        .pcm_mix(dut_pcm_mix), .voice_active(dut_voice_active),
        .voice_pcm(dut_voice_pcm), .voice_busy(dut_voice_busy),
        .deadline_miss(dut_deadline_miss),
        .timbre_blend(timbre_blend), .timbre_busy(timbre_busy)
    );

    four_voice_harmonic_audio_core #(
        .SAMPLE_DIV(64),
        .HARMONICS(32),
        .TIMBRE_BLEND_SAMPLES(256)
    ) u_ref (
        .clk_audio_ref(clk), .rst_n(rst_n),
        .note_on(note_on), .note_off(note_off),
        .velocity_level(8'hff), .phase_inc(phase_inc),
        .timbre_select(1'b0),
        .sustain_enable(1'b0),
        .sample_tick(), .sample_valid(ref_sample_valid),
        .pcm_mix(ref_pcm_mix), .voice_active(ref_voice_active),
        .voice_pcm(ref_voice_pcm), .voice_busy(ref_voice_busy),
        .deadline_miss(ref_deadline_miss),
        .timbre_blend(), .timbre_busy()
    );

    always #5 clk = ~clk;

    integer sample_count;
    integer different_pcm_count;
    integer guard;
    integer k;
    reg switching_active;
    reg [8:0] previous_blend;

    task pulse_note_on;
        begin
            @(negedge clk);
            note_on = 4'b0001;
            @(negedge clk);
            note_on = 4'd0;
        end
    endtask

    task wait_next_sample;
        integer starting_count;
        begin
            starting_count = sample_count;
            while (sample_count == starting_count)
                @(posedge clk);
            #1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            sample_count = 0;
        end
        else if (dut_sample_valid) begin
            sample_count = sample_count + 1;

            if (ref_sample_valid !== 1'b1) begin
                $display("FAIL: timbre DUT/reference sample misalignment");
                $finish;
            end
            if ((dut_deadline_miss !== 4'd0) ||
                (ref_deadline_miss !== 4'd0) ||
                (dut_voice_busy !== 4'd0) || (ref_voice_busy !== 4'd0)) begin
                $display("FAIL: timbre schedule miss/busy sample=%0d miss=%b/%b busy=%b/%b",
                         sample_count, dut_deadline_miss, ref_deadline_miss,
                         dut_voice_busy, ref_voice_busy);
                $finish;
            end
            if ((dut_voice_active !== ref_voice_active) ||
                (u_dut.u_voice0.u_voice_envelope.env_level !==
                 u_ref.u_voice0.u_voice_envelope.env_level) ||
                (u_dut.u_voice0.u_voice_envelope.state !==
                 u_ref.u_voice0.u_voice_envelope.state)) begin
                $display("FAIL: timbre switch changed note lifecycle sample=%0d",
                         sample_count);
                $finish;
            end
            if (switching_active &&
                (u_dut.u_voice0.u_voice_envelope.state == STATE_ATTACK)) begin
                $display("FAIL: timbre switch retriggered Attack sample=%0d",
                         sample_count);
                $finish;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        note_on = 4'd0;
        note_off = 4'd0;
        timbre_select = 1'b0;
        switching_active = 1'b0;
        different_pcm_count = 0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        pulse_note_on;
        wait_next_sample;
        if ((u_dut.u_voice0.u_voice_envelope.state !== STATE_ATTACK) ||
            !dut_voice_active[0]) begin
            $display("FAIL: note did not enter Attack before timbre test");
            $finish;
        end

        guard = 0;
        while ((u_dut.u_voice0.u_voice_envelope.state == STATE_ATTACK) &&
               (guard < 48)) begin
            wait_next_sample;
            guard = guard + 1;
        end
        if ((guard == 48) || !dut_voice_active[0]) begin
            $display("FAIL: note did not leave Attack before timbre switch");
            $finish;
        end
        if ((timbre_blend !== 9'd0) || (dut_voice_pcm[23:0] !== ref_voice_pcm[23:0])) begin
            $display("FAIL: classic profile did not match reference before switch");
            $finish;
        end

        @(negedge clk);
        timbre_select = 1'b1;
        switching_active = 1'b1;
        previous_blend = timbre_blend;
        while (timbre_blend < 9'd256) begin
            wait_next_sample;
            if (timbre_blend !== previous_blend + 9'd1) begin
                $display("FAIL: rock fade step got=%0d previous=%0d",
                         timbre_blend, previous_blend);
                $finish;
            end
            previous_blend = timbre_blend;
        end
        if (timbre_busy !== 1'b0) begin
            $display("FAIL: rock fade remained busy at blend=256");
            $finish;
        end

        for (k = 0; k < 64; k = k + 1) begin
            wait_next_sample;
            if (dut_voice_pcm[23:0] !== ref_voice_pcm[23:0])
                different_pcm_count = different_pcm_count + 1;
        end
        if (different_pcm_count < 32) begin
            $display("FAIL: rock profile PCM was not observably distinct count=%0d",
                     different_pcm_count);
            $finish;
        end

        @(negedge clk);
        timbre_select = 1'b0;
        previous_blend = timbre_blend;
        while (timbre_blend > 9'd0) begin
            wait_next_sample;
            if (timbre_blend !== previous_blend - 9'd1) begin
                $display("FAIL: classic fade step got=%0d previous=%0d",
                         timbre_blend, previous_blend);
                $finish;
            end
            previous_blend = timbre_blend;
        end
        if (timbre_busy !== 1'b0) begin
            $display("FAIL: classic fade remained busy at blend=0");
            $finish;
        end

        for (k = 0; k < 8; k = k + 1) begin
            wait_next_sample;
            if ((dut_voice_pcm[23:0] !== ref_voice_pcm[23:0]) ||
                (dut_pcm_mix !== ref_pcm_mix)) begin
                $display("FAIL: classic profile did not return to reference sample=%0d",
                         sample_count);
                $finish;
            end
        end

        $display("PASS: classic/rock 32-harmonic timbre crossfade, no retrigger and no deadline miss");
        $finish;
    end

endmodule
