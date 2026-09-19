`timescale 1ns/1ps

// Verifies all four strings and all open/fret-1..8 note selections.
module tb_all_note_frequencies;

    reg clk;
    reg rst_n;
    reg stable_valid;
    reg [15:0] stable_fret_id;
    reg [3:0] pluck_valid;
    reg sample_ce;
    reg [5:0] rom_addr;

    wire [31:0] rom_phase_inc;
    wire [3:0] note_on;
    wire [3:0] note_off;
    wire [3:0] slide_valid;
    wire [3:0] voice_active;
    wire [15:0] current_fret_id;
    wire [127:0] target_phase_inc;
    wire [127:0] phase_inc;
    wire [3:0] slide_busy;

    note_phase_table u_note_phase_table (
        .addr     (rom_addr),
        .phase_inc(rom_phase_inc)
    );

    four_string_voice_control #(
        .SLIDE_SAMPLES(4)
    ) u_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .stable_valid    (stable_valid),
        .stable_fret_id  (stable_fret_id),
        .pluck_valid     (pluck_valid),
        .sample_ce       (sample_ce),
        .note_on         (note_on),
        .note_off        (note_off),
        .slide_valid     (slide_valid),
        .voice_active    (voice_active),
        .current_fret_id (current_fret_id),
        .target_phase_inc(target_phase_inc),
        .phase_inc       (phase_inc),
        .slide_busy      (slide_busy)
    );

    always #5 clk = ~clk;

    function [31:0] expected_phase;
        input integer index;
        begin
            case (index)
                 0: expected_phase = 32'h01C20D2F;
                 1: expected_phase = 32'h01DCD01D;
                 2: expected_phase = 32'h01F92A6D;
                 3: expected_phase = 32'h02173456;
                 4: expected_phase = 32'h02370783;
                 5: expected_phase = 32'h0258BF26;
                 6: expected_phase = 32'h027C780B;
                 7: expected_phase = 32'h02A250BA;
                 8: expected_phase = 32'h02CA6987;
                 9: expected_phase = 32'h0151285D;
                10: expected_phase = 32'h016534C3;
                11: expected_phase = 32'h017A725A;
                12: expected_phase = 32'h0190F347;
                13: expected_phase = 32'h01A8CAC3;
                14: expected_phase = 32'h01C20D2F;
                15: expected_phase = 32'h01DCD01D;
                16: expected_phase = 32'h01F92A6D;
                17: expected_phase = 32'h02173456;
                18: expected_phase = 32'h010B9A2B;
                19: expected_phase = 32'h011B83C2;
                20: expected_phase = 32'h012C5F93;
                21: expected_phase = 32'h013E3C06;
                22: expected_phase = 32'h0151285D;
                23: expected_phase = 32'h016534C3;
                24: expected_phase = 32'h017A725A;
                25: expected_phase = 32'h0190F347;
                26: expected_phase = 32'h01A8CAC3;
                27: expected_phase = 32'h00C879A3;
                28: expected_phase = 32'h00D46562;
                29: expected_phase = 32'h00E10697;
                30: expected_phase = 32'h00EE680F;
                31: expected_phase = 32'h00FC9536;
                32: expected_phase = 32'h010B9A2B;
                33: expected_phase = 32'h011B83C2;
                34: expected_phase = 32'h012C5F93;
                default: expected_phase = 32'h013E3C06;
            endcase
        end
    endfunction

    // Independent twelve-tone equal-temperament targets in microhertz.
    function [63:0] expected_frequency_uhz;
        input integer index;
        begin
            case (index)
                 0: expected_frequency_uhz = 64'd329627557;
                 1: expected_frequency_uhz = 64'd349228231;
                 2: expected_frequency_uhz = 64'd369994423;
                 3: expected_frequency_uhz = 64'd391995436;
                 4: expected_frequency_uhz = 64'd415304698;
                 5: expected_frequency_uhz = 64'd440000000;
                 6: expected_frequency_uhz = 64'd466163762;
                 7: expected_frequency_uhz = 64'd493883301;
                 8: expected_frequency_uhz = 64'd523251131;
                 9: expected_frequency_uhz = 64'd246941651;
                10: expected_frequency_uhz = 64'd261625565;
                11: expected_frequency_uhz = 64'd277182631;
                12: expected_frequency_uhz = 64'd293664768;
                13: expected_frequency_uhz = 64'd311126984;
                14: expected_frequency_uhz = 64'd329627557;
                15: expected_frequency_uhz = 64'd349228231;
                16: expected_frequency_uhz = 64'd369994423;
                17: expected_frequency_uhz = 64'd391995436;
                18: expected_frequency_uhz = 64'd195997718;
                19: expected_frequency_uhz = 64'd207652349;
                20: expected_frequency_uhz = 64'd220000000;
                21: expected_frequency_uhz = 64'd233081881;
                22: expected_frequency_uhz = 64'd246941651;
                23: expected_frequency_uhz = 64'd261625565;
                24: expected_frequency_uhz = 64'd277182631;
                25: expected_frequency_uhz = 64'd293664768;
                26: expected_frequency_uhz = 64'd311126984;
                27: expected_frequency_uhz = 64'd146832384;
                28: expected_frequency_uhz = 64'd155563492;
                29: expected_frequency_uhz = 64'd164813778;
                30: expected_frequency_uhz = 64'd174614116;
                31: expected_frequency_uhz = 64'd184997211;
                32: expected_frequency_uhz = 64'd195997718;
                33: expected_frequency_uhz = 64'd207652349;
                34: expected_frequency_uhz = 64'd220000000;
                default: expected_frequency_uhz = 64'd233081881;
            endcase
        end
    endfunction

    function [31:0] selected_target;
        input integer string_index;
        begin
            case (string_index)
                0: selected_target = target_phase_inc[31:0];
                1: selected_target = target_phase_inc[63:32];
                2: selected_target = target_phase_inc[95:64];
                default: selected_target = target_phase_inc[127:96];
            endcase
        end
    endfunction

    function [31:0] selected_phase;
        input integer string_index;
        begin
            case (string_index)
                0: selected_phase = phase_inc[31:0];
                1: selected_phase = phase_inc[63:32];
                2: selected_phase = phase_inc[95:64];
                default: selected_phase = phase_inc[127:96];
            endcase
        end
    endfunction

    task pulse_stable;
        input [15:0] fret_value;
        begin
            @(negedge clk);
            stable_fret_id = fret_value;
            stable_valid = 1'b1;
            @(negedge clk);
            stable_valid = 1'b0;
            #1;
        end
    endtask

    task audio_sample;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            @(negedge clk);
            sample_ce = 1'b0;
            #1;
        end
    endtask

    integer index;
    integer string_index;
    integer fret;
    reg [15:0] all_frets;
    reg [31:0] previous_phase [0:3];
    reg [63:0] phase_product;
    reg [63:0] realized_frequency_uhz;
    reg [63:0] target_frequency_uhz;
    reg [63:0] absolute_error_uhz;
    reg [63:0] maximum_error_uhz;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        stable_valid = 1'b0;
        stable_fret_id = 16'h0000;
        pluck_valid = 4'd0;
        sample_ce = 1'b0;
        rom_addr = 6'd0;
        maximum_error_uhz = 64'd0;
        previous_phase[0] = 32'd0;
        previous_phase[1] = 32'd0;
        previous_phase[2] = 32'd0;
        previous_phase[3] = 32'd0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Check all 36 ROM entries against an independent fixed scoreboard
        // and enforce the README frequency error limit of 0.5 percent.
        for (index = 0; index < 36; index = index + 1) begin
            rom_addr = index[5:0];
            #1;

            if (rom_phase_inc !== expected_phase(index)) begin
                $display("FAIL: phase ROM index=%0d got=%h expected=%h",
                         index, rom_phase_inc, expected_phase(index));
                $finish;
            end

            phase_product = rom_phase_inc * 64'd48000000000;
            realized_frequency_uhz =
                (phase_product + 64'd2147483648) / 64'd4294967296;
            target_frequency_uhz = expected_frequency_uhz(index);

            if (realized_frequency_uhz >= target_frequency_uhz)
                absolute_error_uhz = realized_frequency_uhz -
                                     target_frequency_uhz;
            else
                absolute_error_uhz = target_frequency_uhz -
                                     realized_frequency_uhz;

            if (absolute_error_uhz > maximum_error_uhz)
                maximum_error_uhz = absolute_error_uhz;

            if (absolute_error_uhz * 64'd200 > target_frequency_uhz) begin
                $display("FAIL: frequency error exceeds 0.5 percent index=%0d target_uHz=%0d realized_uHz=%0d",
                         index, target_frequency_uhz,
                         realized_frequency_uhz);
                $finish;
            end
        end

        // Drive all four strings through the same fret number.  This covers
        // the string-to-ROM address mapping using only nine control updates.
        for (fret = 0; fret <= 8; fret = fret + 1) begin
            all_frets = {fret[3:0], fret[3:0], fret[3:0], fret[3:0]};
            pulse_stable(all_frets);

            if ((note_on !== 4'd0) || (note_off !== 4'd0) ||
                (slide_valid !== 4'd0) || (voice_active !== 4'd0) ||
                (current_fret_id !== all_frets)) begin
                $display("FAIL: inactive fret selection emitted an event fret=%0d",
                         fret);
                $finish;
            end

            for (string_index = 0; string_index < 4;
                 string_index = string_index + 1) begin
                index = string_index * 9 + fret;
                if (selected_target(string_index) !== expected_phase(index)) begin
                    $display("FAIL: control mapping string=%0d fret=%0d got=%h expected=%h",
                             string_index, fret,
                             selected_target(string_index),
                             expected_phase(index));
                    $finish;
                end
                if ((fret > 0) &&
                    (selected_target(string_index) <=
                     previous_phase[string_index])) begin
                    $display("FAIL: pitch not monotonic string=%0d fret=%0d",
                             string_index, fret);
                    $finish;
                end
                previous_phase[string_index] = selected_target(string_index);
            end

            audio_sample;
            if (phase_inc !== target_phase_inc || slide_busy !== 4'd0) begin
                $display("FAIL: inactive phase update fret=%0d phase=%h target=%h busy=%b",
                         fret, phase_inc, target_phase_inc, slide_busy);
                $finish;
            end
        end

        $display("PASS: all 36 string/fret phase increments and frequency errors, max_error_uHz=%0d",
                 maximum_error_uhz);
        $finish;
    end

endmodule
