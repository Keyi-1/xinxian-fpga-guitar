`timescale 1ns/1ps

module tb_neo_full_guitar_top;
    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg pixel_clk;
    reg rst_n;
    tri [3:0] fret_row_n;
    reg [7:0] fret_col_in_n;
    reg adc_miso;
    reg key_timbre_n;
    reg key_chorus_n;
    reg key_sustain_n;

    wire adc_cs_n;
    wire adc_sclk;
    wire adc_mosi;
    wire dac_bclk;
    wire dac_lrck;
    wire dac_din;
    wire pa_en_n;
    wire lcd_pclk;
    wire lcd_backlight;
    wire lcd_hsync;
    wire lcd_vsync;
    wire lcd_de;
    wire [7:0] lcd_r;
    wire [7:0] lcd_g;
    wire [7:0] lcd_b;

    integer row;
    integer low_count;
    integer z_count;

    neo_full_guitar_top #(
        .MATRIX_CLK_DIV(1), .MATRIX_SETTLE_CYCLES(0),
        .MATRIX_DEBOUNCE_FRAMES(1), .SAMPLE_DIV(8),
        .PT8211_REF_DIV(1), .SLIDE_SAMPLES(8),
        .ADC_SPI_CLK_DIV(1), .ADC_DEAD_SAMPLES(2),
        .FFT_FRAME_GAP_SAMPLES(8),
        .H_ACTIVE(32), .H_FRONT(2), .H_SYNC(2), .H_BACK(2),
        .V_ACTIVE(16), .V_FRONT(1), .V_SYNC(1), .V_BACK(1),
        .BAR_SLOT(1), .BAR_WIDTH(1),
        .KEY_DEBOUNCE_CYCLES(3),
        .LCD_PCLK_INVERT(1), .LCD_BL_ACTIVE_HIGH(1)
    ) dut (
        .sys_clk_50m(sys_clk_50m),
        .audio_clk_12m288(audio_clk_12m288), .pixel_clk(pixel_clk),
        .rst_n(rst_n), .fret_row_n(fret_row_n),
        .fret_col_in_n(fret_col_in_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .key_timbre_n(key_timbre_n), .key_chorus_n(key_chorus_n),
        .key_sustain_n(key_sustain_n),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck), .dac_din(dac_din),
        .pa_en_n(pa_en_n), .lcd_pclk(lcd_pclk),
        .lcd_backlight(lcd_backlight), .lcd_hsync(lcd_hsync),
        .lcd_vsync(lcd_vsync), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b)
    );

    always #10 sys_clk_50m = ~sys_clk_50m;
    always #7 audio_clk_12m288 = ~audio_clk_12m288;
    always #5 pixel_clk = ~pixel_clk;

    task check_rows;
        begin
            low_count = 0;
            z_count = 0;
            for (row = 0; row < 4; row = row + 1) begin
                if (fret_row_n[row] === 1'b0)
                    low_count = low_count + 1;
                else if (fret_row_n[row] === 1'bz)
                    z_count = z_count + 1;
                else begin
                    $display("FAIL: fret row %0d is neither driven-low nor high-Z", row);
                    $fatal;
                end
            end
            if ((low_count != 1) || (z_count != 3)) begin
                $display("FAIL: fret row tri-state low=%0d z=%0d", low_count, z_count);
                $fatal;
            end
        end
    endtask

    task press_timbre;
        begin
            key_timbre_n = 1'b0;
            repeat (8) @(posedge sys_clk_50m);
            key_timbre_n = 1'b1;
            repeat (8) @(posedge sys_clk_50m);
        end
    endtask

    initial begin
        sys_clk_50m = 1'b0;
        audio_clk_12m288 = 1'b0;
        pixel_clk = 1'b0;
        rst_n = 1'b0;
        fret_col_in_n = 8'hff;
        adc_miso = 1'b0;
        key_timbre_n = 1'b1;
        key_chorus_n = 1'b1;
        key_sustain_n = 1'b1;

        repeat (6) @(posedge sys_clk_50m);
        rst_n = 1'b1;
        repeat (8) @(posedge sys_clk_50m);

        if (lcd_backlight !== 1'b1) begin
            $display("FAIL: LCD backlight did not enable after reset");
            $fatal;
        end
        if (pa_en_n !== 1'b1) begin
            $display("FAIL: speaker amplifier is not muted while idle");
            $fatal;
        end

        repeat (8) begin
            @(posedge sys_clk_50m);
            #1 check_rows();
        end

        @(posedge pixel_clk);
        #1;
        if (lcd_pclk !== ~pixel_clk) begin
            $display("FAIL: LCD pixel-clock inversion mismatch");
            $fatal;
        end

        press_timbre();
        if (dut.timbre_select_sys !== 1'b1) begin
            $display("FAIL: first KEY1 press did not toggle timbre");
            $fatal;
        end
        repeat (4) @(posedge audio_clk_12m288);
        if (dut.timbre_select_audio !== 1'b1) begin
            $display("FAIL: KEY1 state did not cross into audio clock domain");
            $fatal;
        end

        key_timbre_n = 1'b0;
        repeat (16) @(posedge sys_clk_50m);
        if (dut.timbre_select_sys !== 1'b0) begin
            $display("FAIL: second KEY1 press did not toggle timbre off");
            $fatal;
        end
        repeat (12) @(posedge sys_clk_50m);
        if (dut.timbre_select_sys !== 1'b0) begin
            $display("FAIL: held KEY1 generated more than one toggle");
            $fatal;
        end
        key_timbre_n = 1'b1;
        repeat (8) @(posedge sys_clk_50m);

        key_chorus_n = 1'b0;
        key_sustain_n = 1'b0;
        repeat (8) @(posedge sys_clk_50m);
        key_chorus_n = 1'b1;
        key_sustain_n = 1'b1;
        repeat (8) @(posedge sys_clk_50m);
        repeat (4) @(posedge audio_clk_12m288);
        if ((dut.chorus_enable_audio !== 1'b1) ||
            (dut.sustain_reverb_enable_audio !== 1'b1)) begin
            $display("FAIL: KEY2/KEY3 toggle or CDC mismatch");
            $fatal;
        end

        force dut.core_pa_enable = 1'b1;
        #1;
        if (pa_en_n !== 1'b0) begin
            $display("FAIL: active-low PA enable polarity is wrong");
            $fatal;
        end
        release dut.core_pa_enable;
        #1;
        if (pa_en_n !== 1'b1) begin
            $display("FAIL: PA did not return to idle mute");
            $fatal;
        end

        rst_n = 1'b0;
        #1;
        if ((pa_en_n !== 1'b1) || (lcd_backlight !== 1'b0)) begin
            $display("FAIL: reset did not force safe PA/LCD levels");
            $fatal;
        end

        $display("PASS: NEO board wrapper tri-state/buttons/CDC/PA/LCD boundary");
        $finish;
    end

endmodule
