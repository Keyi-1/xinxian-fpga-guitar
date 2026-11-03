`timescale 1ns/1ps
// Writes actual RTL PCM16 for an identical 3- and 4-note audition.
module tb_antibeat_pcm_compare;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, stable_valid = 0;
    reg [15:0] frets = 16'h8852; // F#4/E4/D#4/A#3
    reg [3:0] pluck = 0;
    wire tick0, tick1, valid0, valid1;
    wire [3:0] active0, active1;
    wire [95:0] voices0, voices1;
    four_string_board_audio_chain #(.ANTI_BEAT_ENABLE(0)) old_chain (
        .rock_select(1'b0),
        .clk_audio_ref(clk), .rst_n(rst_n), .stable_valid(stable_valid),
        .stable_fret_id(frets), .pluck_valid(pluck), .velocity_level(8'haa),
        .timbre_select(1'b0), .chorus_enable(1'b0), .sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .sample_tick(tick0), .pcm_mix_valid(valid0), .pcm_mix(),
        .voice_active(active0), .voice_pcm(voices0), .dac_bclk(), .dac_lrck(), .dac_din()
    ,
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );
    four_string_board_audio_chain #(.ANTI_BEAT_ENABLE(1)) new_chain (
        .rock_select(1'b0),
        .clk_audio_ref(clk), .rst_n(rst_n), .stable_valid(stable_valid),
        .stable_fret_id(frets), .pluck_valid(pluck), .velocity_level(8'haa),
        .timbre_select(1'b0), .chorus_enable(1'b0), .sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .sample_tick(tick1), .pcm_mix_valid(valid1), .pcm_mix(),
        .voice_active(active1), .voice_pcm(voices1), .dac_bclk(), .dac_lrck(), .dac_din()
    ,
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );
    integer old_file, new_file, frame = 0, voices_seen = 0;
    reg recording = 0;
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (tick0 !== tick1 || valid0 !== valid1 || voices0 !== voices1 ||
                active0 !== active1)
                $fatal(1, "FAIL: mitigation changed core cadence/pitch/envelopes/lifecycle");
            if (recording && new_chain.pcm16_left_valid) begin
                if (!old_chain.pcm16_left_valid)
                    $fatal(1, "FAIL: mitigation changed PCM16 cadence");
                $fwrite(old_file,"%04h %04h\n",old_chain.pcm16_left_out,old_chain.pcm16_right_out);
                $fwrite(new_file,"%04h %04h\n",new_chain.pcm16_left_out,new_chain.pcm16_right_out);
                frame = frame + 1;
                if (active1 == 15) voices_seen = 1;
            end
        end
    end
    task launch(input [3:0] mask);
        begin
            @(negedge clk); pluck = mask;
            @(negedge clk); pluck = 0;
        end
    endtask
    integer round;
    initial begin
        old_file = $fopen("antibeat_before_pcm16.txt","w");
        new_file = $fopen("antibeat_after_pcm16.txt","w");
        if (!old_file || !new_file) $fatal(1, "FAIL: PCM comparison export");
        repeat (8) @(negedge clk); rst_n = 1;
        @(negedge clk); stable_valid = 1;
        @(negedge clk); stable_valid = 0;
        repeat (512) @(negedge clk);
        recording = 1;
        for (round = 0; round < 4; round = round + 1) begin
            launch(round < 2 ? 4'b0111 : 4'b1111);
            wait(frame >= (round+1)*24000);
        end
        recording = 0;
        if (!voices_seen || frame != 96000)
            $fatal(1, "FAIL: comparison duration or four-note chord missing");
        $fclose(old_file); $fclose(new_file);
        $display("PASS: 96000-frame actual RTL A/B export; per-voice PCM/cadence/lifecycle identical");
        $finish;
    end
    initial begin #260000000; $fatal(1, "FAIL: anti-beat A/B timeout"); end
endmodule
