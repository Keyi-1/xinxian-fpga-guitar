`timescale 1ns/1ps

module tb_full_guitar_top;
    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg pixel_clk;
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
    wire lcd_de;
    wire [7:0] lcd_r;
    wire [7:0] lcd_g;
    wire [7:0] lcd_b;
    wire [3:0] audio_voice_active;
    wire spectrum_frame_update;
    wire display_frame_update;
    wire display_cdc_overrun;

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

    full_guitar_top #(
        .MATRIX_CLK_DIV(2), .MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(2), .SAMPLE_DIV(64),
        .PT8211_REF_DIV(1), .SLIDE_SAMPLES(4),
        .ADC_SPI_CLK_DIV(2), .ADC_DEAD_SAMPLES(2), .ADC_SETTLE_SAMPLES(2), .FIXED_VELOCITY_ENABLE(0),
        .FFT_FRAME_GAP_SAMPLES(8),
        .H_ACTIVE(64), .H_FRONT(2), .H_SYNC(4), .H_BACK(2),
        .V_ACTIVE(32), .V_FRONT(1), .V_SYNC(2), .V_BACK(1),
        .BAR_SLOT(2), .BAR_WIDTH(1)
    ) dut (
        .sys_clk_50m(sys_clk_50m), .audio_clk_12m288(audio_clk_12m288),
        .pixel_clk(pixel_clk), .rst_n(rst_n),
        .fret_col_in_n(fret_col_in_n), .adc_miso(adc_miso),
        .timbre_select(1'b1), .chorus_enable(1'b1),
        .sustain_reverb_enable(1'b1),
        .fret_row_oe(fret_row_oe), .fret_row_drive_n(fret_row_drive_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din),
        .pa_en(), .lcd_hsync(), .lcd_vsync(), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .audio_voice_active(audio_voice_active),
        .spectrum_frame_update(spectrum_frame_update),
        .display_frame_update(display_frame_update),
        .display_cdc_overrun(display_cdc_overrun)
    );

    always #5 sys_clk_50m = ~sys_clk_50m;
    always #7 audio_clk_12m288 = ~audio_clk_12m288;
    always #6 pixel_clk = ~pixel_clk;

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
                adc_selected_data = adc_value_for_channel(
                    {adc_command[2:1], adc_mosi});
            end
            adc_rising_count = adc_rising_count + 1;
        end
    end
    always @(negedge adc_sclk) begin
        if (!adc_cs_n) begin
            if ((adc_rising_count >= 7) && (adc_rising_count <= 18))
                adc_miso = adc_selected_data[18-adc_rising_count];
            else
                adc_miso = 1'b0;
        end
    end

    integer bit_count;
    integer frame_count;
    integer serial_errors;
    integer nonzero_frames;
    integer colored_pixels;
    integer spectrum_updates;
    integer display_updates;
    reg [15:0] expected_left;
    reg [15:0] expected_right;

    always @(posedge dac_bclk) begin
        if (bit_count == 0) begin
            expected_left = dut.u_guitar_audio_top.u_board_audio_chain.u_pt8211_tx.current_left;
            expected_right = dut.u_guitar_audio_top.u_board_audio_chain.u_pt8211_tx.current_right;
        end
        if (bit_count < 16) begin
            if ((dut.dac_lrck !== 1'b0) ||
                (dut.dac_din !== expected_left[15-bit_count]))
                serial_errors = serial_errors + 1;
        end
        else if ((dut.dac_lrck !== 1'b1) ||
                 (dut.dac_din !== expected_right[31-bit_count]))
            serial_errors = serial_errors + 1;
        if (bit_count == 31) begin
            frame_count = frame_count + 1;
            if (expected_left != 0) nonzero_frames = nonzero_frames + 1;
            bit_count = 0;
        end
        else bit_count = bit_count + 1;
    end

    always @(posedge pixel_clk) begin
        #1;
        if (lcd_de && ({lcd_r, lcd_g, lcd_b} != 24'd0))
            colored_pixels = colored_pixels + 1;
        if (display_frame_update)
            display_updates = display_updates + 1;
    end
    always @(posedge audio_clk_12m288)
        if (spectrum_frame_update) spectrum_updates = spectrum_updates + 1;

    initial begin
        sys_clk_50m = 1'b0;
        audio_clk_12m288 = 1'b0;
        pixel_clk = 1'b0;
        rst_n = 1'b0;
        pressed = 32'd0;
        adc_miso = 1'b0;
        adc_value0 = 12'd2053;
        adc_value1 = 12'd2053;
        adc_value2 = 12'd2053;
        adc_value3 = 12'd2053;
        adc_command = 0;
        adc_channel = 0;
        adc_selected_data = 0;
        adc_rising_count = 0;
        bit_count = 0;
        frame_count = 0;
        serial_errors = 0;
        nonzero_frames = 0;
        colored_pixels = 0;
        spectrum_updates = 0;
        display_updates = 0;

        repeat (5) @(posedge sys_clk_50m);
        #1 rst_n = 1'b1;
        pressed = 32'h40080201;
        adc_value0 = 12'd2153;
        adc_value1 = 12'd2253;
        adc_value2 = 12'd2453;
        adc_value3 = 12'd2853;
        wait (audio_voice_active == 4'b1111);
        wait (frame_count >= 2000);
        #1;
        if ((serial_errors != 0) || (nonzero_frames == 0)) begin
            $display("FAIL: FULL PT8211 errors=%0d nonzero=%0d",
                     serial_errors, nonzero_frames);
            $finish;
        end
        if ((spectrum_updates == 0) || (display_updates == 0) ||
            (colored_pixels == 0) || display_cdc_overrun) begin
            $display("FAIL: FULL display spectrum=%0d display=%0d pixels=%0d overrun=%b",
                     spectrum_updates, display_updates, colored_pixels,
                     display_cdc_overrun);
            $finish;
        end
        $display("PASS: FULL matrix/ADC/four-voice/effects/PT8211/FFT/RGB frames=%0d spectrum=%0d pixels=%0d",
                 frame_count, spectrum_updates, colored_pixels);
        $finish;
    end
endmodule
