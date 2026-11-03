`timescale 1ns/1ps

module tb_four_string_audio_chain;

    reg         clk;
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

    wire        sample_tick;
    wire        sample_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0]  audio_voice_active;
    wire signed [95:0] voice_pcm;

    wire signed [23:0] voice_pcm0 = voice_pcm[23:0];
    wire signed [23:0] voice_pcm1 = voice_pcm[47:24];
    wire signed [23:0] voice_pcm2 = voice_pcm[71:48];
    wire signed [23:0] voice_pcm3 = voice_pcm[95:72];

    four_string_voice_control #(
        .SLIDE_SAMPLES(4), .VIBRATO_EXIT_INTERVAL(0)
    ) u_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .stable_valid    (stable_valid),
        .stable_fret_id  (stable_fret_id),
        .pluck_valid     (pluck_valid),
        .sample_ce       (sample_tick),
        .note_on         (note_on),
        .note_off        (note_off),
        .slide_valid     (slide_valid),
        .vibrato_enable(),
        .voice_active    (control_voice_active),
        .current_fret_id (current_fret_id),
        .target_phase_inc(target_phase_inc),
        .phase_inc       (phase_inc),
        .slide_busy      (slide_busy)
    );

    four_voice_audio_core #(
        .SAMPLE_DIV(4)
    ) u_audio (
        .clk_audio_ref(clk),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_off     (note_off),
        .velocity_level(8'hFF),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (sample_valid),
        .pcm_mix      (pcm_mix),
        .voice_active (audio_voice_active),
        .voice_pcm    (voice_pcm)
    );

    always #5 clk = ~clk;

    function signed [23:0] sat_mix4;
        input signed [23:0] a;
        input signed [23:0] b;
        input signed [23:0] c;
        input signed [23:0] d;
        reg signed [25:0] sum;
        begin
            sum = $signed({{2{a[23]}}, a}) +
                  $signed({{2{b[23]}}, b}) +
                  $signed({{2{c[23]}}, c}) +
                  $signed({{2{d[23]}}, d});

            if (sum > 26'sd8388607)
                sat_mix4 = 24'sh7fffff;
            else if (sum < -26'sd8388608)
                sat_mix4 = 24'sh800000;
            else
                sat_mix4 = sum[23:0];
        end
    endfunction

    task pulse_stable;
        input [15:0] fret_id_value;
        begin
            @(negedge clk);
            stable_fret_id = fret_id_value;
            stable_valid   = 1'b1;
            @(negedge clk);
            stable_valid   = 1'b0;
            #1;
        end
    endtask

    task pulse_pluck;
        input [3:0] pluck_value;
        begin
            @(negedge clk);
            pluck_valid = pluck_value;
            @(negedge clk);
            pluck_valid = 4'd0;
            #1;
        end
    endtask

    task wait_audio_sample;
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
        end
    endtask

    task check_mixer_sample;
        reg signed [23:0] expected_mix;
        begin
            expected_mix = sat_mix4(voice_pcm0, voice_pcm1,
                                    voice_pcm2, voice_pcm3);
            if (pcm_mix !== expected_mix) begin
                $display("FAIL: integrated mixer mismatch pcm_mix=%0d expected=%0d v0=%0d v1=%0d v2=%0d v3=%0d",
                         pcm_mix, expected_mix,
                         voice_pcm0, voice_pcm1, voice_pcm2, voice_pcm3);
                $finish;
            end
        end
    endtask

    integer k;
    reg [3:0] nonzero_voice_seen;

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        stable_valid   = 1'b0;
        stable_fret_id = 16'h0000;
        pluck_valid    = 4'd0;
        nonzero_voice_seen = 4'd0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        // Select four different frets before plucking:
        // string0 fret1, string1 fret2, string2 fret4, string3 fret7.
        pulse_stable(16'h7421);
        wait_audio_sample;

        if ((target_phase_inc[31:0]   !== 32'h01DCD01D) ||
            (target_phase_inc[63:32]  !== 32'h017A725A) ||
            (target_phase_inc[95:64]  !== 32'h0151285D) ||
            (target_phase_inc[127:96] !== 32'h012C5F93)) begin
            $display("FAIL: four-string different pitch target selection");
            $finish;
        end

        if (phase_inc !== target_phase_inc) begin
            $display("FAIL: inactive strings did not take pitch targets immediately");
            $finish;
        end

        // A short four-string pluck must be latched by the audio core until
        // the next sample tick, causing all four independent voices to start.
        pulse_pluck(4'b1111);
        wait_audio_sample;
        if ((note_on !== 4'b0000) || (audio_voice_active !== 4'b1111)) begin
            $display("FAIL: four simultaneous plucks were not retained to audio sample");
            $finish;
        end

        for (k = 0; k < 80; k = k + 1) begin
            wait_audio_sample;
            check_mixer_sample;

            if (voice_pcm0 !== 24'sd0) nonzero_voice_seen[0] = 1'b1;
            if (voice_pcm1 !== 24'sd0) nonzero_voice_seen[1] = 1'b1;
            if (voice_pcm2 !== 24'sd0) nonzero_voice_seen[2] = 1'b1;
            if (voice_pcm3 !== 24'sd0) nonzero_voice_seen[3] = 1'b1;

            @(posedge clk);
            #1;
        end

        if (nonzero_voice_seen !== 4'b1111) begin
            $display("FAIL: not all four voices produced nonzero PCM mask=%b",
                     nonzero_voice_seen);
            $finish;
        end

        // Release string 2 only. The controller should issue note_off[2]
        // and the other controller voices should remain active.
        pulse_stable(16'h7021);
        if ((note_off !== 4'b0100) ||
            (control_voice_active !== 4'b1011) ||
            (target_phase_inc[95:64] !== 32'h0151285D)) begin
            $display("FAIL: string 2 independent release control");
            $finish;
        end

        wait_audio_sample;
        if (audio_voice_active !== 4'b1111) begin
            $display("FAIL: released string should enter Release without stopping other audio voices active=%b",
                     audio_voice_active);
            $finish;
        end

        // Release string 3 later; string 1 must remain sounding.
        pulse_stable(16'h0021);
        if ((note_off !== 4'b1000) ||
            (control_voice_active[1] !== 1'b1)) begin
            $display("FAIL: delayed string 3 release affected string 1");
            $finish;
        end

        wait_audio_sample;
        if (audio_voice_active[1] !== 1'b1) begin
            $display("FAIL: string 1 audio voice stopped after another string release");
            $finish;
        end

        // Release string 0 at a third time; string 1 still remains active.
        pulse_stable(16'h0020);
        if ((note_off !== 4'b0001) ||
            (control_voice_active[1] !== 1'b1)) begin
            $display("FAIL: delayed string 0 release affected string 1");
            $finish;
        end

        // Re-select and re-pluck string 2. This must create a fresh note_on
        // for string 2 only, without requiring changes to other strings.
        pulse_stable(16'h0520);
        pulse_pluck(4'b0100);
        if ((note_on !== 4'b0100) ||
            (control_voice_active[2] !== 1'b1) ||
            (target_phase_inc[95:64] !== 32'h016534C3)) begin
            $display("FAIL: string 2 retrigger after release");
            $finish;
        end

        wait_audio_sample;
        if (audio_voice_active[2] !== 1'b1) begin
            $display("FAIL: string 2 audio voice did not retrigger");
            $finish;
        end
        check_mixer_sample;

        $display("PASS: four-string control to four-voice audio chain integration");
        $finish;
    end

endmodule
