`timescale 1ns/1ps

module tb_guitar_audio_top;

    reg         sys_clk_50m;
    reg         audio_clk_12m288;
    reg         rst_n;
    reg [31:0]  pressed;
    reg [3:0]   pluck_valid_sys;

    wire [7:0]  fret_col_in_n;
    wire [3:0]  fret_row_oe;
    wire [3:0]  fret_row_drive_n;
    wire        dac_bclk;
    wire        dac_lrck;
    wire        dac_din;
    wire [31:0] stable_fret_mask;
    wire [15:0] stable_fret_id;
    wire [3:0]  audio_voice_active;

    // Diode-isolated active-low matrix model.
    assign fret_col_in_n = fret_row_oe[0] ? ~pressed[7:0]   :
                           fret_row_oe[1] ? ~pressed[15:8]  :
                           fret_row_oe[2] ? ~pressed[23:16] :
                           fret_row_oe[3] ? ~pressed[31:24] :
                           8'hff;

    guitar_audio_top #(
        .MATRIX_CLK_DIV        (2),
        .MATRIX_SETTLE_CYCLES  (1),
        .MATRIX_DEBOUNCE_FRAMES(2),
        .SAMPLE_DIV            (64),
        .PT8211_REF_DIV        (1),
        .SLIDE_SAMPLES         (4)
    ) dut (
        .sys_clk_50m      (sys_clk_50m),
        .audio_clk_12m288 (audio_clk_12m288),
        .rst_n            (rst_n),
        .fret_col_in_n    (fret_col_in_n),
        .pluck_valid_sys  (pluck_valid_sys),
        .fret_row_oe      (fret_row_oe),
        .fret_row_drive_n (fret_row_drive_n),
        .dac_bclk         (dac_bclk),
        .dac_lrck         (dac_lrck),
        .dac_din          (dac_din),
        .stable_fret_mask (stable_fret_mask),
        .stable_fret_id   (stable_fret_id),
        .audio_voice_active(audio_voice_active)
    );

    // Deliberately unrelated periods exercise both CDC paths.
    always #5 sys_clk_50m = ~sys_clk_50m;
    always #7 audio_clk_12m288 = ~audio_clk_12m288;

    task pulse_pluck_sys;
        input [3:0] value;
        begin
            @(negedge sys_clk_50m);
            pluck_valid_sys = value;
            @(negedge sys_clk_50m);
            pluck_valid_sys = 4'd0;
        end
    endtask

    task wait_stable_fret;
        input [15:0] expected_id;
        integer guard;
        begin
            guard = 0;
            while (stable_fret_id !== expected_id) begin
                @(posedge sys_clk_50m);
                #1;
                guard = guard + 1;
                if (guard > 1000) begin
                    $display("FAIL: stable fret timeout expected=%h got=%h",
                             expected_id, stable_fret_id);
                    $finish;
                end
            end
        end
    endtask

    task wait_audio_active;
        input [3:0] expected_active;
        integer guard;
        begin
            guard = 0;
            while (audio_voice_active !== expected_active) begin
                @(posedge audio_clk_12m288);
                #1;
                guard = guard + 1;
                if (guard > 2000) begin
                    $display("FAIL: audio active timeout expected=%b got=%b",
                             expected_active, audio_voice_active);
                    $finish;
                end
            end
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
            expected_left = dut.u_four_string_audio_chain
                               .u_four_voice_audio_output
                               .u_pt8211_tx.current_left;
            expected_right = dut.u_four_string_audio_chain
                                .u_four_voice_audio_output
                                .u_pt8211_tx.current_right;
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
        sys_clk_50m       = 1'b0;
        audio_clk_12m288  = 1'b0;
        rst_n             = 1'b0;
        pressed           = 32'd0;
        pluck_valid_sys   = 4'd0;
        bit_count         = 0;
        frame_count       = 0;
        error_count       = 0;
        nonzero_frame_count = 0;
        expected_left     = 16'd0;
        expected_right    = 16'd0;

        repeat (5) @(posedge sys_clk_50m);
        #1 rst_n = 1'b1;

        // Frets 1, 2, 4, and 7 on strings 0 through 3 respectively.
        pressed = 32'h40080201;
        wait_stable_fret(16'h7421);

        // A one-system-clock pluck pulse must cross safely into audio clock.
        pulse_pluck_sys(4'b1111);
        wait_audio_active(4'b1111);

        // Releasing string 2 enters Release but preserves other voices.
        pressed = 32'h40000201;
        wait_stable_fret(16'h7021);
        wait_audio_active(4'b1111);

        wait (frame_count >= 10000);
        #1;
        if (error_count != 0) begin
            $display("FAIL: PT8211 protocol errors=%0d", error_count);
            $finish;
        end
        if (nonzero_frame_count == 0) begin
            $display("FAIL: top chain produced only zero PT8211 frames");
            $finish;
        end

        $display("PASS: matrix and pluck CDC through four-string PT8211 top, frames=%0d nonzero=%0d",
                 frame_count, nonzero_frame_count);
        $finish;
    end

endmodule
