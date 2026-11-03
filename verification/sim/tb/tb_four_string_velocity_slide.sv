`timescale 1ns/1ps

module tb_four_string_velocity_slide;

    reg         clk;
    reg         rst_n;
    reg         stable_valid;
    reg [15:0]  stable_fret_id;
    reg [3:0]   pluck_valid;
    reg [7:0]   velocity_level;

    wire [3:0]   note_on;
    wire [3:0]   note_off;
    wire [3:0]   slide_valid;
    wire [3:0]   control_voice_active;
    wire [127:0] target_phase_inc;
    wire [127:0] phase_inc;
    wire [3:0]   slide_busy;
    wire         sample_tick;
    wire [3:0]   audio_voice_active;

    four_string_audio_chain #(
        .SAMPLE_DIV   (4),
        .REF_DIV      (1),
        .SLIDE_SAMPLES(4)
    ) dut (
        .clk_audio_ref       (clk),
        .rst_n               (rst_n),
        .stable_valid        (stable_valid),
        .stable_fret_id      (stable_fret_id),
        .pluck_valid         (pluck_valid),
        .velocity_level      (velocity_level),
        .note_on             (note_on),
        .note_off            (note_off),
        .slide_valid         (slide_valid),
        .control_voice_active(control_voice_active),
        .current_fret_id     (),
        .target_phase_inc    (target_phase_inc),
        .phase_inc           (phase_inc),
        .slide_busy          (slide_busy),
        .sample_tick         (sample_tick),
        .pcm_mix_valid       (),
        .pcm_mix             (),
        .audio_voice_active  (audio_voice_active),
        .voice_pcm           (),
        .pcm16_valid         (),
        .pcm16_out           (),
        .dac_bclk            (),
        .dac_lrck            (),
        .dac_din             ()
    );

    always #5 clk = ~clk;

    task pulse_stable;
        input [15:0] value;
        begin
            @(negedge clk);
            stable_fret_id = value;
            stable_valid = 1'b1;
            @(negedge clk);
            stable_valid = 1'b0;
            #1;
        end
    endtask

    task pulse_pluck;
        input [3:0] value;
        begin
            @(negedge clk);
            pluck_valid = value;
            @(negedge clk);
            pluck_valid = 4'd0;
            #1;
        end
    endtask

    task wait_sample;
        begin
            @(negedge sample_tick);
            #1;
        end
    endtask

    integer k;
    reg [2:0] state0_before_slide;
    reg [2:0] state1_before_slide;
    reg [31:0] phase0_before_slide;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        stable_valid = 1'b0;
        stable_fret_id = 16'h0000;
        pluck_valid = 4'd0;
        // String 0 is light and string 1 is heavy.
        velocity_level = 8'b00001100;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        // Select string 0 fret 3 and leave string 1 on its open pitch.
        pulse_stable(16'h0003);
        wait_sample;

        pulse_pluck(4'b0011);
        wait_sample;
        if (audio_voice_active[1:0] !== 2'b11) begin
            $display("FAIL: two velocity voices did not start");
            $finish;
        end

        // Let both envelopes complete Attack before beginning the slide.
        for (k = 0; k < 32; k = k + 1)
            wait_sample;

        if ((dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice0.u_voice_envelope.attack_target !== 16'd12288) ||
            (dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice1.u_voice_envelope.attack_target !== 16'd32767)) begin
            $display("FAIL: different velocity targets were not latched");
            $finish;
        end

        state0_before_slide = dut.u_four_voice_audio_output.u_four_voice_audio_core
                                  .u_voice0.u_voice_envelope.state;
        state1_before_slide = dut.u_four_voice_audio_output.u_four_voice_audio_core
                                  .u_voice1.u_voice_envelope.state;
        phase0_before_slide = phase_inc[31:0];
        if ((state0_before_slide === 3'd1) || (state1_before_slide === 3'd1)) begin
            $display("FAIL: envelope remained in Attack before slide");
            $finish;
        end

        // Fret 3 -> fret 4 on string 0 must create a slide only.
        pulse_stable(16'h0004);
        if ((slide_valid !== 4'b0001) || (note_on !== 4'b0000) ||
            (note_off !== 4'b0000)) begin
            $display("FAIL: slide generated a note event");
            $finish;
        end

        wait_sample;
        if ((phase_inc[31:0] == phase0_before_slide) ||
            (phase_inc[31:0] == target_phase_inc[31:0]) ||
            (slide_busy[0] !== 1'b1)) begin
            $display("FAIL: phase increment did not begin a continuous slide");
            $finish;
        end
        if ((dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice0.u_voice_envelope.state !== state0_before_slide) ||
            (dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice1.u_voice_envelope.state !== state1_before_slide) ||
            (dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice0.u_voice_envelope.attack_target !== 16'd12288) ||
            (dut.u_four_voice_audio_output.u_four_voice_audio_core
                 .u_voice1.u_voice_envelope.attack_target !== 16'd32767)) begin
            $display("FAIL: slide changed envelope state or velocity target");
            $finish;
        end

        for (k = 0; k < 3; k = k + 1)
            wait_sample;
        if ((phase_inc[31:0] !== target_phase_inc[31:0]) ||
            (slide_busy[0] !== 1'b0)) begin
            $display("FAIL: slide did not reach target phase increment");
            $finish;
        end

        $display("PASS: slide preserves envelope state and per-string velocity");
        $finish;
    end

endmodule
