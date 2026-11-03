`timescale 1ns/1ps

module tb_four_voice_harmonic_audio_output;

    reg clk_audio_ref;
    reg rst_n;
    reg [3:0] note_on;
    reg [3:0] note_off;
    reg timbre_select;
    reg chorus_enable;
    reg sustain_reverb_enable;
    reg [127:0] phase_inc;
    wire sample_tick;
    wire pcm_mix_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0] voice_active;
    wire signed [95:0] voice_pcm;
    wire [3:0] voice_busy;
    wire [3:0] deadline_miss;
    wire [8:0] timbre_blend;
    wire timbre_busy;
    wire [8:0] chorus_blend;
    wire chorus_busy;
    wire [8:0] reverb_blend;
    wire reverb_busy;
    wire pcm16_valid;
    wire signed [15:0] pcm16_out;
    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;

    // A 64-cycle sample period gives 32 cycles to finish each harmonic voice,
    // while REF_DIV=1 produces one 32-bit stereo frame every 64 reference clocks.
    four_voice_harmonic_audio_output #(
        .SAMPLE_DIV(64), .REF_DIV(1), .HARMONICS(32)
    ) dut (
        .clk_audio_ref(clk_audio_ref), .rst_n(rst_n),
        .note_on(note_on), .note_off(note_off), .velocity_level(8'hFF),
        .phase_inc(phase_inc), .timbre_select(timbre_select),
        .chorus_enable(chorus_enable),
        .sustain_reverb_enable(sustain_reverb_enable),
        .sample_tick(sample_tick),
        .pcm_mix_valid(pcm_mix_valid), .pcm_mix(pcm_mix),
        .voice_active(voice_active), .voice_pcm(voice_pcm),
        .voice_busy(voice_busy), .deadline_miss(deadline_miss),
        .timbre_blend(timbre_blend), .timbre_busy(timbre_busy),
        .chorus_blend(chorus_blend), .chorus_busy(chorus_busy),
        .reverb_blend(reverb_blend), .reverb_busy(reverb_busy),
        .pcm16_valid(pcm16_valid), .pcm16_out(pcm16_out),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din)
    );

    always #5 clk_audio_ref = ~clk_audio_ref;

    function signed [15:0] pcm24_to_16_reference;
        input signed [23:0] pcm_in;
        reg signed [24:0] pcm_ext;
        reg signed [24:0] magnitude;
        reg signed [24:0] scaled_value;
        begin
            pcm_ext = {pcm_in[23], pcm_in};
            if (pcm_ext < 0) begin
                magnitude = -pcm_ext;
                scaled_value = -((magnitude + 25'sd128) >>> 8);
            end
            else begin
                magnitude = pcm_ext;
                scaled_value = (magnitude + 25'sd128) >>> 8;
            end
            if (scaled_value > 25'sd32767)
                pcm24_to_16_reference = 16'sh7fff;
            else if (scaled_value < -25'sd32768)
                pcm24_to_16_reference = 16'sh8000;
            else
                pcm24_to_16_reference = scaled_value[15:0];
        end
    endfunction

    integer bit_count;
    integer frame_count;
    integer error_count;
    integer nonzero_frame_count;
    integer clipped_sample_count;
    integer chorus_changed_count;
    integer reverb_changed_count;
    reg [15:0] expected_left;
    reg [15:0] expected_right;

    always @(posedge pcm16_valid) begin
        #1;
        if (pcm16_out !== pcm24_to_16_reference(pcm_mix))
            error_count = error_count + 1;
    end

    always @(posedge pcm_mix_valid) begin
        #1;
        if ((timbre_blend == 9'd256) &&
            (pcm_mix !== dut.pcm_mix_raw))
            clipped_sample_count = clipped_sample_count + 1;
        if ((chorus_blend == 9'd256) && (reverb_blend == 9'd0) &&
            (dut.pcm_chorus !== dut.pcm_clip))
            chorus_changed_count = chorus_changed_count + 1;
        if ((reverb_blend == 9'd256) &&
            (pcm_mix !== dut.pcm_chorus))
            reverb_changed_count = reverb_changed_count + 1;
    end

    always @(posedge dac_bclk) begin
        if (bit_count == 0) begin
            expected_left = dut.u_pt8211_tx.current_left;
            expected_right = dut.u_pt8211_tx.current_right;
        end
        if (bit_count < 16) begin
            if (dac_lrck !== 1'b0 || dac_din !== expected_left[15-bit_count])
                error_count = error_count + 1;
        end
        else begin
            if (dac_lrck !== 1'b1 || dac_din !== expected_right[31-bit_count])
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
        else
            bit_count = bit_count + 1;
    end

    initial begin
        clk_audio_ref = 1'b0;
        rst_n = 1'b0;
        note_on = 4'd0;
        note_off = 4'd0;
        timbre_select = 1'b0;
        chorus_enable = 1'b0;
        sustain_reverb_enable = 1'b0;
        phase_inc = {32'h00C879A3, 32'h010B9A2B,
                     32'h0151285D, 32'h01C20D2F};
        bit_count = 0;
        frame_count = 0;
        error_count = 0;
        nonzero_frame_count = 0;
        clipped_sample_count = 0;
        chorus_changed_count = 0;
        reverb_changed_count = 0;
        expected_left = 16'd0;
        expected_right = 16'd0;

        repeat (5) @(posedge clk_audio_ref);
        #1 rst_n = 1'b1;
        @(negedge clk_audio_ref);
        note_on = 4'b1111;
        @(negedge clk_audio_ref);
        note_on = 4'd0;

        wait (frame_count >= 100);
        @(negedge clk_audio_ref);
        timbre_select = 1'b1;
        wait (timbre_blend == 9'd256);

        wait (frame_count >= 500);
        @(negedge clk_audio_ref);
        chorus_enable = 1'b1;
        wait (chorus_blend == 9'd256);

        wait (frame_count >= 900);
        @(negedge clk_audio_ref);
        sustain_reverb_enable = 1'b1;
        wait (reverb_blend == 9'd256);

        wait (frame_count >= 1600);
        @(negedge clk_audio_ref);
        chorus_enable = 1'b0;
        wait (chorus_blend == 9'd0);

        wait (frame_count >= 2000);
        #1;
        if (error_count != 0) begin
            $display("FAIL: harmonic PT8211 protocol/conversion errors=%0d", error_count);
            $finish;
        end
        if (voice_active !== 4'b1111) begin
            $display("FAIL: harmonic voices are not active mask=%b", voice_active);
            $finish;
        end
        if (deadline_miss !== 4'd0 || voice_busy !== 4'd0) begin
            $display("FAIL: harmonic output schedule deadline_miss=%b busy=%b",
                     deadline_miss, voice_busy);
            $finish;
        end
        if (nonzero_frame_count == 0) begin
            $display("FAIL: harmonic output produced only zero PT8211 frames");
            $finish;
        end
        if (timbre_busy || (clipped_sample_count == 0)) begin
            $display("FAIL: rock soft clip was not active busy=%b count=%0d",
                     timbre_busy, clipped_sample_count);
            $finish;
        end
        if (chorus_busy || reverb_busy || (chorus_blend != 9'd0) ||
            (reverb_blend != 9'd256) || (chorus_changed_count == 0) ||
            (reverb_changed_count == 0)) begin
            $display("FAIL: independent effects blend/busy/change chorus=%0d/%b/%0d reverb=%0d/%b/%0d",
                     chorus_blend, chorus_busy, chorus_changed_count,
                     reverb_blend, reverb_busy, reverb_changed_count);
            $finish;
        end

        $display("PASS: independent rock/chorus/reverb effects to PT8211, frames=%0d clipped=%0d chorus=%0d reverb=%0d",
                 frame_count, clipped_sample_count, chorus_changed_count,
                 reverb_changed_count);
        $finish;
    end

endmodule
