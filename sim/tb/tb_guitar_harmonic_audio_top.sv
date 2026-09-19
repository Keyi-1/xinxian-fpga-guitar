`timescale 1ns/1ps

module tb_guitar_harmonic_audio_top;

    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg rst_n;
    reg [31:0] pressed;
    wire [7:0] fret_col_in_n;
    wire [3:0] fret_row_oe;
    wire [3:0] fret_row_drive_n;
    wire adc_cs_n;
    wire adc_sclk;
    wire adc_mosi;
    reg adc_miso;
    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;
    wire [15:0] stable_fret_id;
    wire [3:0] audio_voice_active;
    wire [7:0] velocity_level;
    reg [11:0] adc_value0;
    reg [11:0] adc_value1;
    reg [11:0] adc_value2;
    reg [11:0] adc_value3;
    reg [4:0] adc_command;
    reg [2:0] adc_channel;
    reg [11:0] adc_selected_data;
    integer adc_rising_count;

    assign fret_col_in_n = fret_row_oe[0] ? ~pressed[7:0] :
                           fret_row_oe[1] ? ~pressed[15:8] :
                           fret_row_oe[2] ? ~pressed[23:16] :
                           fret_row_oe[3] ? ~pressed[31:24] : 8'hff;

    guitar_audio_top #(
        .MATRIX_CLK_DIV(2), .MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(2), .SAMPLE_DIV(64), .PT8211_REF_DIV(1),
        .SLIDE_SAMPLES(4), .ADC_SPI_CLK_DIV(2), .ADC_DEAD_SAMPLES(2),
        .USE_HARMONIC(1)
    ) dut (
        .sys_clk_50m(sys_clk_50m), .audio_clk_12m288(audio_clk_12m288),
        .rst_n(rst_n), .fret_col_in_n(fret_col_in_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .timbre_select(1'b0), .chorus_enable(1'b0),
        .sustain_reverb_enable(1'b0),
        .fret_row_oe(fret_row_oe),
        .fret_row_drive_n(fret_row_drive_n), .dac_bclk(dac_bclk),
        .dac_lrck(dac_lrck), .dac_din(dac_din), .stable_fret_mask(),
        .stable_fret_id(stable_fret_id), .audio_voice_active(audio_voice_active),
        .velocity_level(velocity_level), .raw_adc(), .peak_adc(),
        .event_timestamp()
    );

    always #5 sys_clk_50m = ~sys_clk_50m;
    always #7 audio_clk_12m288 = ~audio_clk_12m288;

    function [11:0] adc_value_for_channel;
        input [2:0] channel;
        begin
            case (channel)
                3'd0: adc_value_for_channel = adc_value0;
                3'd1: adc_value_for_channel = adc_value1;
                3'd2: adc_value_for_channel = adc_value2;
                default: adc_value_for_channel = adc_value3;
            endcase
        end
    endfunction

    always @(negedge adc_cs_n) begin
        adc_command = 5'd0;
        adc_channel = 3'd0;
        adc_selected_data = 12'd0;
        adc_rising_count = 0;
        adc_miso = 1'b0;
    end

    always @(posedge adc_sclk) begin
        if (!adc_cs_n) begin
            if (adc_rising_count < 5)
                adc_command[4-adc_rising_count] = adc_mosi;
            if (adc_rising_count == 4) begin
                adc_channel = {adc_command[2:1], adc_mosi};
                adc_selected_data = adc_value_for_channel({adc_command[2:1], adc_mosi});
            end
            adc_rising_count = adc_rising_count + 1;
        end
    end

    always @(negedge adc_sclk) begin
        if (!adc_cs_n) begin
            if ((adc_rising_count >= 6) && (adc_rising_count <= 17))
                adc_miso = adc_selected_data[17-adc_rising_count];
            else
                adc_miso = 1'b0;
        end
    end

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
                    $display("FAIL: harmonic top stable fret timeout");
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
                if (guard > 3000) begin
                    $display("FAIL: harmonic top audio active timeout");
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
            expected_left = dut.u_harmonic_audio_path.u_four_string_harmonic_audio_chain
                            .u_four_voice_harmonic_audio_output.u_pt8211_tx.current_left;
            expected_right = dut.u_harmonic_audio_path.u_four_string_harmonic_audio_chain
                             .u_four_voice_harmonic_audio_output.u_pt8211_tx.current_right;
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
        sys_clk_50m = 1'b0;
        audio_clk_12m288 = 1'b0;
        rst_n = 1'b0;
        pressed = 32'd0;
        adc_miso = 1'b0;
        adc_value0 = 12'd0;
        adc_value1 = 12'd0;
        adc_value2 = 12'd0;
        adc_value3 = 12'd0;
        adc_command = 5'd0;
        adc_channel = 3'd0;
        adc_selected_data = 12'd0;
        adc_rising_count = 0;
        bit_count = 0;
        frame_count = 0;
        error_count = 0;
        nonzero_frame_count = 0;
        expected_left = 16'd0;
        expected_right = 16'd0;

        repeat (5) @(posedge sys_clk_50m);
        #1 rst_n = 1'b1;
        pressed = 32'h40080201;
        wait_stable_fret(16'h7421);
        adc_value0 = 12'd1200;
        adc_value1 = 12'd1700;
        adc_value2 = 12'd2400;
        adc_value3 = 12'd3300;
        wait_audio_active(4'b1111);
        if (velocity_level !== 8'hE4) begin
            $display("FAIL: harmonic top ADC velocity levels=%h", velocity_level);
            $finish;
        end
        wait (frame_count >= 2000);
        #1;
        if (error_count != 0) begin
            $display("FAIL: harmonic top PT8211 errors=%0d", error_count);
            $finish;
        end
        if (nonzero_frame_count == 0) begin
            $display("FAIL: harmonic top produced only zero PT8211 frames");
            $finish;
        end
        $display("PASS: matrix and MCP3208 through harmonic PT8211 top, frames=%0d nonzero=%0d",
                 frame_count, nonzero_frame_count);
        $finish;
    end

endmodule
