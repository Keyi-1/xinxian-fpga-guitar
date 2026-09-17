`timescale 1ns/1ps

module tb_four_string_audio_output_chain;

    reg         clk_audio_ref;
    reg         rst_n;
    reg         stable_valid;
    reg [15:0]  stable_fret_id;
    reg [3:0]   pluck_valid;

    wire [3:0]   note_on;
    wire [3:0]   note_off;
    wire [3:0]   slide_valid;
    wire [3:0]   control_voice_active;
    wire [15:0]  current_fret_id;
    wire [127:0] target_phase_inc;
    wire [127:0] phase_inc;
    wire [3:0]   slide_busy;
    wire         sample_tick;
    wire         pcm_mix_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0]   audio_voice_active;
    wire signed [95:0] voice_pcm;
    wire         pcm16_valid;
    wire signed [15:0] pcm16_out;
    wire         dac_bclk;
    wire         dac_lrck;
    wire         dac_din;

    four_string_audio_chain #(
        .SAMPLE_DIV   (64),
        .REF_DIV      (1),
        .SLIDE_SAMPLES(4)
    ) dut (
        .clk_audio_ref       (clk_audio_ref),
        .rst_n               (rst_n),
        .stable_valid        (stable_valid),
        .stable_fret_id      (stable_fret_id),
        .pluck_valid         (pluck_valid),
        .velocity_level      (8'hFF),
        .note_on             (note_on),
        .note_off            (note_off),
        .slide_valid         (slide_valid),
        .control_voice_active(control_voice_active),
        .current_fret_id     (current_fret_id),
        .target_phase_inc    (target_phase_inc),
        .phase_inc           (phase_inc),
        .slide_busy          (slide_busy),
        .sample_tick         (sample_tick),
        .pcm_mix_valid       (pcm_mix_valid),
        .pcm_mix             (pcm_mix),
        .audio_voice_active  (audio_voice_active),
        .voice_pcm           (voice_pcm),
        .pcm16_valid         (pcm16_valid),
        .pcm16_out           (pcm16_out),
        .dac_bclk            (dac_bclk),
        .dac_lrck            (dac_lrck),
        .dac_din             (dac_din)
    );

    always #5 clk_audio_ref = ~clk_audio_ref;

    task pulse_stable;
        input [15:0] value;
        begin
            @(negedge clk_audio_ref);
            stable_fret_id = value;
            stable_valid   = 1'b1;
            @(negedge clk_audio_ref);
            stable_valid   = 1'b0;
        end
    endtask

    task pulse_pluck;
        input [3:0] value;
        begin
            @(negedge clk_audio_ref);
            pluck_valid = value;
            @(negedge clk_audio_ref);
            pluck_valid = 4'd0;
        end
    endtask

    integer bit_count;
    integer frame_count;
    integer error_count;
    integer nonzero_frame_count;
    reg [15:0] expected_left;
    reg [15:0] expected_right;

    always @(posedge dac_bclk) begin
        if (bit_count == 0) begin
            expected_left  = dut.u_four_voice_audio_output.u_pt8211_tx.current_left;
            expected_right = dut.u_four_voice_audio_output.u_pt8211_tx.current_right;
        end

        if (bit_count < 16) begin
            if (dac_lrck !== 1'b0 ||
                dac_din !== expected_left[15-bit_count])
                error_count = error_count + 1;
        end
        else begin
            if (dac_lrck !== 1'b1 ||
                dac_din !== expected_right[31-bit_count])
                error_count = error_count + 1;
        end

        if (bit_count == 31) begin
            frame_count = frame_count + 1;
            if (expected_left !== expected_right)
                error_count = error_count + 1;
            if (expected_left !== 16'd0)
                nonzero_frame_count = nonzero_frame_count + 1;
            bit_count = 0;
        end
        else begin
            bit_count = bit_count + 1;
        end
    end

    initial begin
        clk_audio_ref       = 1'b0;
        rst_n               = 1'b0;
        stable_valid        = 1'b0;
        stable_fret_id      = 16'h0000;
        pluck_valid         = 4'd0;
        bit_count           = 0;
        frame_count         = 0;
        error_count         = 0;
        nonzero_frame_count = 0;
        expected_left       = 16'd0;
        expected_right      = 16'd0;

        repeat (5) @(posedge clk_audio_ref);
        #1 rst_n = 1'b1;

        // Select four different frets, then pluck all four strings.
        pulse_stable(16'h7421);
        @(negedge sample_tick);
        #1;
        if ((target_phase_inc[31:0]   !== 32'h01DCD01D) ||
            (target_phase_inc[63:32]  !== 32'h017A725A) ||
            (target_phase_inc[95:64]  !== 32'h0151285D) ||
            (target_phase_inc[127:96] !== 32'h012C5F93) ||
            (phase_inc !== target_phase_inc)) begin
            $display("FAIL: four-string pitch selection did not reach audio path");
            $finish;
        end

        pulse_pluck(4'b1111);
        @(negedge sample_tick);
        #1;
        if ((control_voice_active !== 4'b1111) ||
            (audio_voice_active !== 4'b1111)) begin
            $display("FAIL: four-string pluck did not activate four audio voices");
            $finish;
        end

        // Releasing string 2 must not stop the other three audio voices.
        pulse_stable(16'h7021);
        if ((note_off !== 4'b0100) ||
            (control_voice_active !== 4'b1011)) begin
            $display("FAIL: string 2 control release");
            $finish;
        end
        @(negedge sample_tick);
        #1;
        if (audio_voice_active !== 4'b1111) begin
            $display("FAIL: string 2 release stopped another audio voice");
            $finish;
        end

        wait (frame_count >= 10000);
        #1;
        if (error_count != 0) begin
            $display("FAIL: PT8211 protocol errors=%0d", error_count);
            $finish;
        end
        if (nonzero_frame_count == 0) begin
            $display("FAIL: end-to-end chain produced only zero PT8211 frames");
            $finish;
        end

        $display("PASS: four-string control through PT8211, frames=%0d nonzero=%0d",
                 frame_count, nonzero_frame_count);
        $finish;
    end

endmodule
