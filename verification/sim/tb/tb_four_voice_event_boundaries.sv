`timescale 1ns/1ps

// Exercises one-cycle note events on both sides of the audio sample boundary.
module tb_four_voice_event_boundaries;

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
        .velocity_level(8'hFF),
        .phase_inc    (phase_inc),
        .sample_tick  (sample_tick),
        .sample_valid (sample_valid),
        .pcm_mix      (pcm_mix),
        .voice_active (voice_active),
        .voice_pcm    (voice_pcm)
    );

    always #5 clk = ~clk;

    task check_release_state;
        input integer voice_index;
        input [2:0] expected_state;
        begin
            case (voice_index)
                0: if (dut.u_voice0.u_voice_envelope.state !== expected_state) begin
                    $display("FAIL: voice 0 envelope state=%0d expected=%0d",
                             dut.u_voice0.u_voice_envelope.state, expected_state);
                    $finish;
                end
                1: if (dut.u_voice1.u_voice_envelope.state !== expected_state) begin
                    $display("FAIL: voice 1 envelope state=%0d expected=%0d",
                             dut.u_voice1.u_voice_envelope.state, expected_state);
                    $finish;
                end
                default: begin
                    $display("FAIL: invalid voice index");
                    $finish;
                end
            endcase
        end
    endtask

    task pulse_note_on_while_tick_low;
        input [3:0] value;
        begin
            @(negedge sample_tick);
            #1 note_on = value;
            @(posedge clk);
            @(negedge clk);
            note_on = 4'd0;
        end
    endtask

    task pulse_note_on_while_tick_high;
        input [3:0] value;
        begin
            @(posedge sample_tick);
            @(negedge clk);
            note_on = value;
            @(negedge clk);
            note_on = 4'd0;
        end
    endtask

    task pulse_note_off_after_tick_consumed;
        input [3:0] value;
        begin
            @(negedge sample_tick);
            #1 note_off = value;
            @(posedge clk);
            @(negedge clk);
            note_off = 4'd0;
        end
    endtask

    task pulse_note_off_while_tick_high;
        input [3:0] value;
        begin
            @(posedge sample_tick);
            @(negedge clk);
            note_off = value;
            @(negedge clk);
            note_off = 4'd0;
        end
    endtask

    initial begin
        clk      = 1'b0;
        rst_n    = 1'b0;
        note_on  = 4'd0;
        note_off = 4'd0;
        phase_inc = {
            32'h00C879A3, 32'h010B9A2B,
            32'h0151285D, 32'h01C20D2F
        };

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // A pulse during tick-low must be retained to the next sample tick.
        pulse_note_on_while_tick_low(4'b0001);
        @(negedge sample_tick);
        #1;
        if (voice_active !== 4'b0001) begin
            $display("FAIL: note_on before sample tick was not delivered");
            $finish;
        end

        // A pulse after tick rises but before it is consumed has the same
        // sample-boundary behavior and must not disturb voice 0.
        pulse_note_on_while_tick_high(4'b0010);
        @(negedge sample_tick);
        #1;
        if (voice_active !== 4'b0011) begin
            $display("FAIL: note_on during sample tick was not delivered");
            $finish;
        end

        // An event just after the consuming edge must wait for the following
        // sample tick. Voice 1 must remain outside Release in the meantime.
        pulse_note_off_after_tick_consumed(4'b0001);
        check_release_state(0, 3'd1);
        check_release_state(1, 3'd1);

        @(negedge sample_tick);
        #1;
        check_release_state(0, 3'd4);
        check_release_state(1, 3'd1);

        // A second release pulse while tick is high must apply at that same
        // boundary and must not alter voice 0's already-active Release.
        pulse_note_off_while_tick_high(4'b0010);
        @(negedge sample_tick);
        #1;
        check_release_state(0, 3'd4);
        check_release_state(1, 3'd4);

        $display("PASS: four-voice note event sample-tick boundaries");
        $finish;
    end

endmodule
