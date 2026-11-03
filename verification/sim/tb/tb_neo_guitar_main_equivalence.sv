`timescale 1ns/1ps
module tb_neo_guitar_main_equivalence;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] pressed = 0;
    reg [11:0] adc_code [0:3];
    tri ROW0, ROW1, ROW2, ROW3;
    wire [7:0] cols = (ROW0 === 0) ? ~pressed[7:0] :
                      (ROW1 === 0) ? ~pressed[15:8] :
                      (ROW2 === 0) ? ~pressed[23:16] :
                      (ROW3 === 0) ? ~pressed[31:24] : 8'hff;
    wire cs_n, sclk, mosi, bclk, lrck, din, pa;
    reg miso = 0;
    wire [3:0] leds;
    neo_guitar_main_top #(
        .USE_PIANO(0),
        .ANTI_BEAT_ENABLE(0),
        .MATRIX_CLK_DIV(2), .MATRIX_SETTLE_CYCLES(2),
        .MATRIX_DEBOUNCE_FRAMES(2), .ADC_SPI_CLK_DIV(2),
        .PLUCK_DEAD_SAMPLES(4), .PLUCK_SETTLE_SAMPLES(2),
        .AUDIO_SAMPLE_DIV(64), .PT8211_REF_DIV(1),
        .SLIDE_SAMPLES(8), .LED_HOLD_CYCLES(128),
        .PLUCK_ATTACK_SAMPLES(4), .PLUCK_FAST_DECAY_SAMPLES(256),
        .PLUCK_FAST_SHIFT(8), .PLUCK_SLOW_SHIFT(10),
        .PLUCK_RELEASE_SHIFT(2)
    ) dut (
        .audio_clk_12m288(clk), .rst_n(rst_n),
        .ROW0(ROW0), .ROW1(ROW1), .ROW2(ROW2), .ROW3(ROW3),
        .COL0(cols[0]), .COL1(cols[1]), .COL2(cols[2]), .COL3(cols[3]),
        .COL4(cols[4]), .COL5(cols[5]), .COL6(cols[6]), .COL7(cols[7]),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_mosi(mosi), .adc_miso(miso),
        .dac_bclk(bclk), .dac_lrck(lrck), .dac_din(din),
        .pa_en_n(pa), .event_led(leds)
    );
    // The runner keeps the original verified audio arithmetic. Below, only
    // its note_off/pitch control inputs are replaced by an independent table
    // policy for the intentional open-release change; audio/ROMs are unforced.
    // Main reset_sync releases in 3 clocks; the reference uses 2 clocks.
    reg ref_rst_n = 0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) ref_rst_n <= 0;
        else ref_rst_n <= 1;
    tri [3:0] ref_rows;
    wire [7:0] ref_cols = (ref_rows[0] === 0) ? ~pressed[7:0] :
                          (ref_rows[1] === 0) ? ~pressed[15:8] :
                          (ref_rows[2] === 0) ? ~pressed[23:16] :
                          (ref_rows[3] === 0) ? ~pressed[31:24] : 8'hff;
    wire ref_cs, ref_sclk, ref_mosi, ref_bclk, ref_lrck, ref_din, ref_pa;
    wire [3:0] ref_leds;
    ref_neo_full_chain_audio_test_top #(
        .MATRIX_CLK_DIV(2), .MATRIX_SETTLE_CYCLES(2),
        .MATRIX_DEBOUNCE_FRAMES(2), .ADC_SPI_CLK_DIV(2),
        .PLUCK_DEAD_SAMPLES(4), .PLUCK_SETTLE_SAMPLES(2),
        .AUDIO_SAMPLE_DIV(64), .PT8211_REF_DIV(1),
        .SLIDE_SAMPLES(8), .LED_HOLD_CYCLES(128),
        .PLUCK_ATTACK_SAMPLES(4), .PLUCK_FAST_DECAY_SAMPLES(256),
        .PLUCK_FAST_SHIFT(8), .PLUCK_SLOW_SHIFT(10),
        .PLUCK_RELEASE_SHIFT(2)
    ) reference (
        .audio_clk_12m288(clk), .rst_n(ref_rst_n),
        .ROW0(ref_rows[0]), .ROW1(ref_rows[1]), .ROW2(ref_rows[2]), .ROW3(ref_rows[3]),
        .COL0(ref_cols[0]), .COL1(ref_cols[1]), .COL2(ref_cols[2]), .COL3(ref_cols[3]),
        .COL4(ref_cols[4]), .COL5(ref_cols[5]), .COL6(ref_cols[6]), .COL7(ref_cols[7]),
        .adc_cs_n(ref_cs), .adc_sclk(ref_sclk), .adc_mosi(ref_mosi), .adc_miso(miso),
        .dac_bclk(ref_bclk), .dac_lrck(ref_lrck), .dac_din(ref_din),
        .pa_en_n(ref_pa), .event_led(ref_leds)
    );
    integer equivalent_clocks = 0;
    always @(posedge clk) begin
        #1;
        check({ROW3,ROW2,ROW1,ROW0} === ref_rows, "reference matrix rows differ");
        check({cs_n,sclk,mosi} === {ref_cs,ref_sclk,ref_mosi}, "reference SPI differs");
        check({bclk,lrck,din,pa,leds} === {ref_bclk,ref_lrck,ref_din,ref_pa,ref_leds},
              "reference stereo DAC, PA or event LEDs differ");
        if (dut.u_audio.audio_rst_n) begin
            check(dut.u_audio.u_board_audio_chain.phase_inc === reference.phase_inc,
                  "reference per-string phase differs");
            check(dut.u_audio.u_board_audio_chain.voice_active === reference.voice_active,
                  "reference voice lifecycle differs");
            check(dut.u_audio.u_board_audio_chain.voice_pcm === reference.voice_pcm,
                  "reference per-string PCM differs");
            equivalent_clocks = equivalent_clocks + 1;
        end
    end

    task check(input bit ok, input string message);
        if (!ok) $fatal(1, "FAIL: %s", message);
    endtask

    // MCP3208 pin-level slave. Start/SGL/D2/D1/D0 are sampled on the first
    // five rising edges. Null is at edge 7, B11 at edge 8, B0 at edge 19.
    // The board-tested master stops at edge 18; its reader reconstructs an
    // odd code (LSB forced to 1). This explicitly tests that known behaviour.
    integer rises = 0;
    integer channel = 0;
    integer expected_channel = 0;
    integer spi_transactions = 0;
    reg [4:0] command = 0;
    reg [11:0] conversion_code = 0;
    reg [11:0] sent_code [0:3];
    always @(negedge cs_n) begin
        rises = 0;
        command = 0;
        miso = 0;
    end
    always @(posedge sclk) if (!cs_n) begin
        rises = rises + 1;
        if (rises <= 5) command = {command[3:0], mosi};
        if (rises == 5) begin
            check(command[4:3] == 2'b11, "ADC command must be single-ended");
            channel = command[2:0];
            check(channel == expected_channel, "ADC CH0..3 round-robin order");
            conversion_code = adc_code[channel];
            sent_code[channel] = {conversion_code[11:1], 1'b1};
        end
    end
    always @(negedge sclk) if (!cs_n) begin
        if (rises >= 7 && rises <= 18)
            miso = conversion_code[18-rises];
        else
            miso = 0;
    end
    always @(posedge cs_n) begin
        if (rst_n && dut.u_audio.audio_rst_n && rises != 0) begin
            check(rises == 18, "preserved ADC transfer length");
            expected_channel = (expected_channel + 1) % 4;
            spi_transactions = spi_transactions + 1;
        end
    end
    always @(negedge rst_n) expected_channel = 0;

    integer cycles = 0;
    integer ons [0:3];
    integer offs [0:3];
    integer detected [0:3];
    integer last_pluck [0:3];
    integer max_launch_delay = 0;
    integer n;
    reg [3:0] nonselected_pcm = 0;
    bit all_pcm = 0;
    bit stereo_nonzero = 0;
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (dut.u_audio.audio_rst_n) begin
            check(pa === 0, "PA stays enabled after reset, including idle");
            if (dut.u_audio.u_mcp3208_pluck_frontend.sample_valid)
                check(dut.u_audio.u_mcp3208_pluck_frontend.sample_data === sent_code[dut.u_audio.u_mcp3208_pluck_frontend.sample_string],
                      "pin-level SPI ADC reconstruction");
            for (n = 0; n < 4; n = n + 1) begin
                if (dut.u_audio.pluck_valid_audio[n]) begin
                    detected[n] = detected[n] + 1;
                    last_pluck[n] = cycles;
                end
                if (dut.u_audio.u_board_audio_chain.note_on[n]) begin
                    ons[n] = ons[n] + 1;
                    check(dut.u_audio.u_board_audio_chain.sample_tick, "note_on is sample aligned");
                    check(ons[n] <= detected[n], "fret alone cannot create note_on");
                    check(cycles-last_pluck[n] <= 64, "no chord-capture delay");
                    if (cycles-last_pluck[n] > max_launch_delay)
                        max_launch_delay = cycles-last_pluck[n];
                end
                if (dut.u_audio.u_board_audio_chain.note_off[n]) offs[n] = offs[n] + 1;
            end
            if (dut.u_audio.u_board_audio_chain.voice_sample_valid && dut.u_audio.u_board_audio_chain.voice_active == 4'b1111) begin
                if (ROW0 !== 0 && dut.u_audio.u_board_audio_chain.voice_pcm0 != 0) nonselected_pcm[0] = 1;
                if (ROW1 !== 0 && dut.u_audio.u_board_audio_chain.voice_pcm1 != 0) nonselected_pcm[1] = 1;
                if (ROW2 !== 0 && dut.u_audio.u_board_audio_chain.voice_pcm2 != 0) nonselected_pcm[2] = 1;
                if (ROW3 !== 0 && dut.u_audio.u_board_audio_chain.voice_pcm3 != 0) nonselected_pcm[3] = 1;
                if (dut.u_audio.u_board_audio_chain.voice_pcm0 != 0 && dut.u_audio.u_board_audio_chain.voice_pcm1 != 0 &&
                    dut.u_audio.u_board_audio_chain.voice_pcm2 != 0 && dut.u_audio.u_board_audio_chain.voice_pcm3 != 0) all_pcm = 1;
            end
            if (dut.u_audio.u_board_audio_chain.pcm16_left_valid && dut.u_audio.u_board_audio_chain.pcm16_left_out != 0 &&
                dut.u_audio.u_board_audio_chain.pcm16_right_out != 0 &&
                dut.u_audio.u_board_audio_chain.pcm16_left_out != dut.u_audio.u_board_audio_chain.pcm16_right_out) stereo_nonzero = 1;
        end
    end

    // Decode the external PT8211 stream against the latest PCM submitted
    // before each frame boundary, rather than forcing an internal signal.
    reg [31:0] latest_pcm = 0;
    reg [31:0] frame_pcm = 0;
    bit decode_ready = 0;
    integer decoded_frames = 0;
    bit serial_nonzero = 0;
    always @(posedge clk) begin
        if (!dut.u_audio.audio_rst_n) latest_pcm = 0;
        else if (dut.u_audio.u_board_audio_chain.pcm16_left_valid)
            latest_pcm = {dut.u_audio.u_board_audio_chain.pcm16_left_out, dut.u_audio.u_board_audio_chain.pcm16_right_out};
    end
    always @(negedge bclk) begin
        #1; // Observe all same-edge nonblocking transmitter updates.
        if (dut.u_audio.audio_rst_n && dut.u_audio.u_board_audio_chain.u_pt8211_tx.bit_count == 0) begin
            frame_pcm = latest_pcm;
            decode_ready = 1;
            decoded_frames = decoded_frames + 1;
            if (frame_pcm != 0) serial_nonzero = 1;
        end
    end
    always @(posedge bclk) begin
        #1;
        if (dut.u_audio.audio_rst_n && decode_ready) begin
            check(din === frame_pcm[31-dut.u_audio.u_board_audio_chain.u_pt8211_tx.bit_count],
                  "PT8211 serial bit differs from submitted stereo PCM");
            check(lrck === (dut.u_audio.u_board_audio_chain.u_pt8211_tx.bit_count >= 16), "PT8211 L/R framing");
        end
    end
    always @(negedge rst_n) decode_ready = 0;

    task wait_fret(input [15:0] value);
        integer guard;
        begin
            guard = 0;
            while (dut.u_audio.stable_fret_id !== value) begin
                @(negedge clk);
                guard = guard + 1;
                check(guard < 1000, "matrix debounce timeout");
            end
            repeat (2) @(negedge clk);
        end
    endtask
    task reset_board;
        integer j;
        begin
            @(negedge clk);
            rst_n = 0;
            pressed = 0;
            for (j = 0; j < 4; j = j + 1) begin
                adc_code[j] = 2053;
                ons[j] = 0; offs[j] = 0; detected[j] = 0; last_pluck[j] = 0;
            end
            repeat (8) @(negedge clk);
            check(pa === 1 && leds == 4'b1111, "reset mutes PA and clears LEDs");
            rst_n = 1;
            repeat (400) @(negedge clk);
            check(dut.u_audio.u_board_audio_chain.voice_active == 0, "reset release must not auto-play");
        end
    endtask
    task wait_on(input integer s, input integer count);
        integer guard;
        begin
            guard = 0;
            while (ons[s] < count) begin
                @(negedge clk);
                guard = guard + 1;
                check(guard < 1500, "real ADC pluck did not reach note_on");
            end
            check(ons[s] == count, "one pluck produced extra note_on");
        end
    endtask
    task wait_armed(input integer s);
        integer guard;
        begin
            guard = 0;
            adc_code[s] = 2053;
            while (!dut.u_audio.u_mcp3208_pluck_frontend.u_four_string_pluck_detector.armed[s]) begin
                @(negedge clk);
                guard = guard + 1;
                check(guard < 3000, "ADC hysteresis/dead-time rearm timeout");
            end
        end
    endtask

    reg [31:0] notes [0:35];
    // The frozen reference retains all its verified audio arithmetic. Only
    // note_off/pitch inputs use this new policy oracle, fed by its own inputs.
    reg [127:0] ref_held_pitch;
    wire [127:0] ref_open_policy_pitch;
    genvar policy_string;
    generate for(policy_string=0;policy_string<4;policy_string++)begin : policy_oracle
        wire [31:0] picked=notes[policy_string*9+reference.stable_fret_id[policy_string*4+:4]];
        assign ref_open_policy_pitch[policy_string*32+:32]=
            (reference.u_link_control.pending_pluck[policy_string] || reference.pluck_valid[policy_string]) ?
            picked : ref_held_pitch[policy_string*32+:32];
        always @(posedge clk)begin
            if(!reference.audio_rst_n)
                case(policy_string)
                    0:ref_held_pitch[policy_string*32+:32]<=32'h01C20D2F;
                    1:ref_held_pitch[policy_string*32+:32]<=32'h0151285D;
                    2:ref_held_pitch[policy_string*32+:32]<=32'h010B9A2B;
                    3:ref_held_pitch[policy_string*32+:32]<=32'h00C879A3;
                endcase
            else if(reference.stable_valid || reference.note_on[policy_string])
                ref_held_pitch[policy_string*32+:32]<=picked;
        end
    end endgenerate
    initial begin
        force reference.note_off=4'd0;
        force reference.target_phase_inc=ref_open_policy_pitch;
    end
    integer s, f, j, old_count, env_early, env_late;
    reg [3:0] old_pan;
    reg [31:0] last_phase;
    initial begin
        $readmemh("note_phase_inc.mem", notes);
        for (j = 0; j < 4; j = j + 1) adc_code[j] = 2053;
        // Cover all 4x9 pitches through the actual matrix and ADC pins.
        for (s = 0; s < 4; s = s + 1) begin
            for (f = 0; f <= 8; f = f + 1) begin
                reset_board();
                if (f != 0) pressed[s*8 +: 8] = 8'b1 << (f-1);
                wait_fret(f << (s*4));
                repeat (200) @(negedge clk);
                check(dut.u_audio.u_board_audio_chain.voice_active == 0 && ons[s] == 0,
                      "fret press must select silently");
                adc_code[s] = 2253;
                wait_on(s, 1);
                check(dut.u_audio.u_board_audio_chain.phase_inc[s*32 +: 32] == notes[s*9+f],
                      "pluck must select the correct open/fretted pitch");
                repeat (4) @(negedge clk);
                check(leds[s] == 0, "pluck LED must light");
            end
        end
        $display("PASS: all 36 pitches select silently and launch only from pin-level MCP3208 plucks");

        reset_board();
        pressed = 32'h08_80_20_01; // F4/F4/D#4/F#3
        wait_fret(16'h4861);
        for (j = 0; j < 4; j = j + 1) adc_code[j] = 2253;
        for (j = 0; j < 4; j = j + 1) wait_on(j, 1);
        repeat (1500) @(negedge clk);
        check(dut.u_audio.u_board_audio_chain.voice_active == 15 && nonselected_pcm == 15 && all_pcm,
              "four voices must run continuously outside their scan rows");
        check(stereo_nonzero && serial_nonzero && decoded_frames > 20,
              "optimized stereo PCM must reach PT8211 pins");
        check(dut.u_audio.u_board_audio_chain.phase_inc[31:0] == dut.u_audio.u_board_audio_chain.phase_inc[63:32], "equal F4 tuning");
        check($countones(dut.u_audio.u_board_audio_chain.voice_pan_right) == 2, "four voices balance 2+2");
        old_pan = dut.u_audio.u_board_audio_chain.voice_pan_right;
        for (j = 0; j < 4; j = j + 1)
            check(ons[j] == 1, "held ADC excursion cannot retrigger");

        // Positive and negative piezo excursions trigger the same string;
        // below-threshold input after rearm stays silent.
        wait_armed(0);
        adc_code[0] = 2103;
        repeat (800) @(negedge clk);
        check(ons[0] == 1, "sub-threshold piezo excursion must not trigger");
        adc_code[0] = 1853;
        wait_on(0, 2);
        check(dut.u_audio.u_board_audio_chain.voice_pan_right == old_pan, "repluck must retain active pan");
        $display("PASS: hysteresis, dead time, bipolar detection and same-string repluck isolation");

        // Two keys in row 0: highest fret wins, then slides down when only
        // the lower key remains. Neither change starts another Attack.
        pressed[7:0] = 8'h09;
        wait_fret(16'h4864);
        check(dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0] != notes[4], "slide must not jump");
        repeat (640) @(negedge clk);
        check(dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0] == notes[4], "slide reaches high fret");
        pressed[7:0] = 8'h01;
        wait_fret(16'h4861);
        repeat (640) @(negedge clk);
        check(dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0] == notes[1], "remaining lower fret slide");
        check(ons[0] == 2 && offs[0] == 0, "slides do not retrigger Attack");

        // Final release slides to open without damping or another Attack.
        last_phase = dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0];
        pressed[7:0] = 0;
        wait_fret(16'h4860);
        repeat (640) @(negedge clk);
        check(offs[0] == 0 && ons[0] == 2 && dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0] == notes[0],
              "last fret release slides to open without Release or Attack");
        check(dut.u_audio.u_board_audio_chain.voice_active == 15, "release preserves all four natural envelopes");
        wait_armed(0);
        adc_code[0] = 2253;
        wait_on(0, 3);
        check(dut.u_audio.u_board_audio_chain.phase_inc[31:0] == notes[0], "repluck after release uses open E4");
        $display("PASS: highest-fret slides, open-string continuation and new real pluck");

        // Held contacts and ADC levels cannot create a sustain plateau or
        // synthetic repeat notes. Read the unchanged optimized envelope.
        repeat (12*64) @(negedge clk);
        env_early = dut.u_audio.u_board_audio_chain.g_sine.u_core.u_voice0.envelope_level;
        repeat (12*64) @(negedge clk);
        env_late = dut.u_audio.u_board_audio_chain.g_sine.u_core.u_voice0.envelope_level;
        check(env_early > env_late && env_late > 0, "natural decay without plateau");
        repeat (1000000) @(negedge clk);
        check(dut.u_audio.u_board_audio_chain.voice_active == 0 && pa == 0, "natural idle keeps PA enabled");
        check(ons[0] == 3 && ons[1] == 1 && ons[2] == 1 && ons[3] == 1,
              "held frets cannot restart after natural decay");

        // Test every possible first-pair combination, including 0+2 / 1+3.
        for (s = 0; s < 4; s = s + 1) begin
            for (f = s+1; f < 4; f = f + 1) begin
                reset_board();
                adc_code[s] = 2253; wait_on(s, 1);
                adc_code[f] = 2253; wait_on(f, 1);
                check(dut.u_audio.u_board_audio_chain.voice_pan_right[s] != dut.u_audio.u_board_audio_chain.voice_pan_right[f],
                      "every first pair must occupy opposite stereo channels");
            end
        end
        $display("PASS: natural decay, all six stereo pairs, constant PA and decoded PT8211 frames");
        $display("PASS: main/reference equivalent_clocks=%0d", equivalent_clocks);
        $display("PASS: integrated link regression; max detected-pluck-to-Attack delay=%0d clocks (limit 64)", max_launch_delay);
        $finish;
    end
    initial begin
        #30000000;
        $fatal(1, "FAIL: full-chain regression timeout");
    end
endmodule
