`timescale 1ns/1ps

module tb_harmonic_voice_core;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg note_on;
    reg note_off;
    reg [6:0] sample_countdown;
    reg first_sample;

    wire sample_valid;
    wire signed [23:0] pcm_out;
    wire [15:0] env_level;
    wire active;
    wire busy;
    wire deadline_miss;

    harmonic_voice_core #(
        .HARMONICS(32)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_ce     (sample_ce),
        .note_on       (note_on),
        .note_off      (note_off),
        .velocity_level(2'd3),
        .phase_inc     (32'h01C20D2F),
        .timbre_blend  (9'd0),
        .sample_valid  (sample_valid),
        .pcm_out       (pcm_out),
        .env_level     (env_level),
        .active        (active),
        .busy          (busy),
        .deadline_miss (deadline_miss)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_countdown <= 7'd0;
            sample_ce <= 1'b0;
            note_on <= 1'b0;
            first_sample <= 1'b1;
        end
        else begin
            sample_ce <= 1'b0;
            note_on <= 1'b0;

            if (sample_countdown == 7'd63) begin
                sample_countdown <= 7'd0;
                sample_ce <= 1'b1;
                if (first_sample) begin
                    note_on <= 1'b1;
                    first_sample <= 1'b0;
                end
            end
            else begin
                sample_countdown <= sample_countdown + 1'b1;
            end
        end
    end

    integer busy_cycles;
    integer result_count;
    integer nonzero_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy_cycles <= 0;
            result_count <= 0;
            nonzero_count <= 0;
        end
        else begin
            if (busy)
                busy_cycles <= busy_cycles + 1;
            else if (busy_cycles != 0) begin
                if (busy_cycles != 32) begin
                    $display("FAIL: harmonic schedule used %0d cycles", busy_cycles);
                    $finish;
                end
                busy_cycles <= 0;
            end

            if (sample_valid) begin
                result_count <= result_count + 1;
                if (pcm_out != 24'sd0)
                    nonzero_count <= nonzero_count + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_ce = 1'b0;
        note_on = 1'b0;
        note_off = 1'b0;
        sample_countdown = 7'd0;
        first_sample = 1'b1;
        busy_cycles = 0;
        result_count = 0;
        nonzero_count = 0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;

        wait (result_count >= 8);
        #1;
        if (deadline_miss !== 1'b0) begin
            $display("FAIL: 32-harmonic engine missed sample deadline");
            $finish;
        end
        if (!active || nonzero_count < 4) begin
            $display("FAIL: harmonic voice did not produce PCM active=%b nonzero=%0d",
                     active, nonzero_count);
            $finish;
        end
        if ((dut.harmonic_amplitude[0] == 0) ||
            (dut.harmonic_amplitude[1] == 0) ||
            (dut.harmonic_amplitude[2] == 0)) begin
            $display("FAIL: harmonic gain configuration was not loaded");
            $finish;
        end

        $display("PASS: 32-harmonic scheduled voice, results=%0d nonzero=%0d",
                 result_count, nonzero_count);
        $finish;
    end

endmodule
