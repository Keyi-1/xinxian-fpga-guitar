`timescale 1ns/1ps

module tb_four_voice_audio_output;

    reg         clk_audio_ref;
    reg         rst_n;
    reg [3:0]   note_on;
    reg [3:0]   note_off;
    reg [127:0] phase_inc;

    wire        sample_tick;
    wire        pcm_mix_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0]  voice_active;
    wire signed [95:0] voice_pcm;
    wire        pcm16_valid;
    wire signed [15:0] pcm16_out;
    wire        dac_bclk;
    wire        dac_lrck;
    wire        dac_din;

    // SAMPLE_DIV equals the 32-bit stereo frame length for REF_DIV=1.
    // This preserves one PCM sample per PT8211 frame while accelerating RTL sim.
    four_voice_audio_output #(
        .SAMPLE_DIV(64),
        .REF_DIV   (1)
    ) dut (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .velocity_level(8'hFF),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .pcm_mix_valid(pcm_mix_valid),
        .pcm_mix      (pcm_mix),
        .voice_active (voice_active),
        .voice_pcm    (voice_pcm),
        .pcm16_valid  (pcm16_valid),
        .pcm16_out    (pcm16_out),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    always #5 clk_audio_ref = ~clk_audio_ref;

    integer bit_count;
    integer frame_count;
    integer error_count;
    integer nonzero_frame_count;
    reg [15:0] expected_left;
    reg [15:0] expected_right;

    function signed [15:0] pcm24_to_16_reference;
        input signed [23:0] pcm_in;
        reg signed [24:0] pcm_ext;
        reg signed [24:0] magnitude;
        reg signed [24:0] scaled_value;
        begin
            pcm_ext = {pcm_in[23], pcm_in};
            if (pcm_ext < 0) begin
                magnitude    = -pcm_ext;
                scaled_value = -((magnitude + 25'sd128) >>> 8);
            end
            else begin
                magnitude    = pcm_ext;
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

    always @(posedge pcm16_valid) begin
        #1;
        if (pcm16_out !== pcm24_to_16_reference(pcm_mix))
            error_count = error_count + 1;
    end

    always @(posedge dac_bclk) begin
        if (bit_count == 0) begin
            expected_left  = dut.u_pt8211_tx.current_left;
            expected_right = dut.u_pt8211_tx.current_right;
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
        clk_audio_ref      = 1'b0;
        rst_n              = 1'b0;
        note_on            = 4'd0;
        note_off           = 4'd0;
        phase_inc          = {
            32'h00C879A3, 32'h010B9A2B,
            32'h0151285D, 32'h01C20D2F
        };
        bit_count          = 0;
        frame_count        = 0;
        error_count        = 0;
        nonzero_frame_count = 0;
        expected_left      = 16'd0;
        expected_right     = 16'd0;

        repeat (5) @(posedge clk_audio_ref);
        #1 rst_n = 1'b1;

        // Start all four independent voices with distinct phase increments.
        @(negedge clk_audio_ref);
        note_on = 4'b1111;
        @(negedge clk_audio_ref);
        note_on = 4'd0;

        wait (frame_count >= 10000);
        #1;

        if (error_count != 0) begin
            $display("FAIL: PT8211 protocol errors=%0d", error_count);
            $finish;
        end
        if (voice_active !== 4'b1111) begin
            $display("FAIL: four voices are not active mask=%b", voice_active);
            $finish;
        end
        if (nonzero_frame_count == 0) begin
            $display("FAIL: four-voice audio chain produced only zero PT8211 frames");
            $finish;
        end

        $display("PASS: four-voice PCM24 to PT8211 output, frames=%0d nonzero=%0d",
                 frame_count, nonzero_frame_count);
        $finish;
    end

endmodule
