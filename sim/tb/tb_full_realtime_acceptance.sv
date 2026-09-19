`timescale 1ns/1ps

// README FULL real-time acceptance:
// - actual 12.288 MHz reference, 48 kHz sample cadence and PT8211 divider
// - at least 10,000 consecutive serial frames
// - four active 32-harmonic voices while effects are switched
// - no sample drop, harmonic deadline miss or display CDC overrun
// - 1024-point spectrum frame cadence remains approximately 30 FPS
module tb_full_realtime_acceptance;
    localparam integer REQUIRED_DAC_FRAMES = 10000;
    localparam integer MIN_SPECTRUM_UPDATES = 5;
    localparam time SPECTRUM_INTERVAL_MIN_NS = 31000000;
    localparam time SPECTRUM_INTERVAL_MAX_NS = 35000000;

    reg sys_clk_50m;
    reg audio_clk_12m288;
    reg pixel_clk;
    reg rst_n;
    reg [31:0] pressed;
    wire [7:0] fret_col_in_n;
    reg adc_miso;
    reg timbre_select;
    reg chorus_enable;
    reg sustain_reverb_enable;

    wire [3:0] fret_row_oe;
    wire [3:0] fret_row_drive_n;
    wire adc_cs_n;
    wire adc_sclk;
    wire adc_mosi;
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

    integer bit_count;
    integer dac_frame_count;
    integer serial_errors;
    integer acceptance_start_frame;
    integer nonzero_acceptance_frames;
    reg [15:0] expected_left;
    reg [15:0] expected_right;

    integer audio_cycle_count;
    integer previous_pcm_cycle;
    integer pcm_sample_count;
    integer pcm_interval_errors;
    integer spectrum_update_count;
    integer display_update_count;
    integer spectrum_interval_errors;
    time previous_spectrum_time;
    time minimum_spectrum_interval;
    time maximum_spectrum_interval;
    reg colored_pixel_seen;

    wire final_pcm_valid = dut.final_pcm_valid;
    wire [3:0] harmonic_deadline_miss =
        dut.u_guitar_audio_top.u_harmonic_audio_path
        .u_four_string_harmonic_audio_chain
        .u_four_voice_harmonic_audio_output.deadline_miss;
    wire [8:0] timbre_blend =
        dut.u_guitar_audio_top.u_harmonic_audio_path
        .u_four_string_harmonic_audio_chain
        .u_four_voice_harmonic_audio_output.timbre_blend;
    wire [8:0] chorus_blend =
        dut.u_guitar_audio_top.u_harmonic_audio_path
        .u_four_string_harmonic_audio_chain
        .u_four_voice_harmonic_audio_output.chorus_blend;
    wire [8:0] reverb_blend =
        dut.u_guitar_audio_top.u_harmonic_audio_path
        .u_four_string_harmonic_audio_chain
        .u_four_voice_harmonic_audio_output.reverb_blend;

    assign fret_col_in_n = fret_row_oe[0] ? ~pressed[7:0] :
                           fret_row_oe[1] ? ~pressed[15:8] :
                           fret_row_oe[2] ? ~pressed[23:16] :
                           fret_row_oe[3] ? ~pressed[31:24] : 8'hff;

    full_guitar_top #(
        .MATRIX_CLK_DIV(2), .MATRIX_SETTLE_CYCLES(1),
        .MATRIX_DEBOUNCE_FRAMES(2),
        .SAMPLE_DIV(256), .PT8211_REF_DIV(4),
        .SLIDE_SAMPLES(960),
        .ADC_SPI_CLK_DIV(25), .ADC_DEAD_SAMPLES(250),
        .FFT_FRAME_GAP_SAMPLES(512)
    ) dut (
        .sys_clk_50m(sys_clk_50m),
        .audio_clk_12m288(audio_clk_12m288),
        .pixel_clk(pixel_clk), .rst_n(rst_n),
        .fret_col_in_n(fret_col_in_n), .adc_miso(adc_miso),
        .timbre_select(timbre_select),
        .chorus_enable(chorus_enable),
        .sustain_reverb_enable(sustain_reverb_enable),
        .fret_row_oe(fret_row_oe),
        .fret_row_drive_n(fret_row_drive_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk),
        .adc_mosi(adc_mosi),
        .dac_bclk(dac_bclk), .dac_lrck(dac_lrck),
        .dac_din(dac_din), .pa_en(),
        .lcd_hsync(), .lcd_vsync(), .lcd_de(lcd_de),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b),
        .audio_voice_active(audio_voice_active),
        .spectrum_frame_update(spectrum_frame_update),
        .display_frame_update(display_frame_update),
        .display_cdc_overrun(display_cdc_overrun)
    );

    always #10 sys_clk_50m = ~sys_clk_50m;
    always #40.690104167 audio_clk_12m288 = ~audio_clk_12m288;
    always #15 pixel_clk = ~pixel_clk;

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
            if ((adc_rising_count >= 6) && (adc_rising_count <= 17))
                adc_miso = adc_selected_data[17-adc_rising_count];
            else
                adc_miso = 1'b0;
        end
    end

    // Serial checker samples exactly where PT8211 samples: BCLK rising edge.
    always @(posedge dac_bclk) begin
        if (bit_count == 0) begin
            expected_left = dut.u_guitar_audio_top.u_harmonic_audio_path
                .u_four_string_harmonic_audio_chain
                .u_four_voice_harmonic_audio_output.u_pt8211_tx.current_left;
            expected_right = dut.u_guitar_audio_top.u_harmonic_audio_path
                .u_four_string_harmonic_audio_chain
                .u_four_voice_harmonic_audio_output.u_pt8211_tx.current_right;
        end

        if (bit_count < 16) begin
            if ((dac_lrck !== 1'b0) ||
                (dac_din !== expected_left[15-bit_count]))
                serial_errors = serial_errors + 1;
        end
        else if ((dac_lrck !== 1'b1) ||
                 (dac_din !== expected_right[31-bit_count]))
            serial_errors = serial_errors + 1;

        if (bit_count == 31) begin
            dac_frame_count = dac_frame_count + 1;
            if ((dac_frame_count > acceptance_start_frame) &&
                ((expected_left != 0) || (expected_right != 0)))
                nonzero_acceptance_frames = nonzero_acceptance_frames + 1;
            bit_count = 0;
        end
        else
            bit_count = bit_count + 1;
    end

    always @(posedge audio_clk_12m288) begin
        audio_cycle_count = audio_cycle_count + 1;
        #1;
        if (final_pcm_valid) begin
            if ((previous_pcm_cycle != 0) &&
                ((audio_cycle_count - previous_pcm_cycle) != 256))
                pcm_interval_errors = pcm_interval_errors + 1;
            previous_pcm_cycle = audio_cycle_count;
            pcm_sample_count = pcm_sample_count + 1;
        end

        if (harmonic_deadline_miss !== 4'd0) begin
            $display("FAIL: FULL harmonic deadline miss mask=%b frame=%0d",
                     harmonic_deadline_miss, dac_frame_count);
            $fatal;
        end
        if ((dac_frame_count >= acceptance_start_frame) &&
            (audio_voice_active !== 4'b1111)) begin
            $display("FAIL: FULL voice dropped during endurance active=%b frame=%0d",
                     audio_voice_active, dac_frame_count);
            $fatal;
        end

        if (spectrum_frame_update) begin
            spectrum_update_count = spectrum_update_count + 1;
            if (previous_spectrum_time != 0) begin
                if (($time - previous_spectrum_time <
                     SPECTRUM_INTERVAL_MIN_NS) ||
                    ($time - previous_spectrum_time >
                     SPECTRUM_INTERVAL_MAX_NS))
                    spectrum_interval_errors =
                        spectrum_interval_errors + 1;
                if (($time - previous_spectrum_time) <
                    minimum_spectrum_interval)
                    minimum_spectrum_interval =
                        $time - previous_spectrum_time;
                if (($time - previous_spectrum_time) >
                    maximum_spectrum_interval)
                    maximum_spectrum_interval =
                        $time - previous_spectrum_time;
            end
            previous_spectrum_time = $time;
        end
    end

    always @(posedge pixel_clk) begin
        #1;
        if (display_frame_update)
            display_update_count = display_update_count + 1;
        if (lcd_de && ({lcd_r, lcd_g, lcd_b} != 24'd0))
            colored_pixel_seen = 1'b1;
    end

    initial begin
        sys_clk_50m = 1'b0;
        audio_clk_12m288 = 1'b0;
        pixel_clk = 1'b0;
        rst_n = 1'b0;
        pressed = 32'h40080201;
        adc_miso = 1'b0;
        timbre_select = 1'b0;
        chorus_enable = 1'b0;
        sustain_reverb_enable = 1'b0;
        adc_value0 = 12'd1200;
        adc_value1 = 12'd1700;
        adc_value2 = 12'd2400;
        adc_value3 = 12'd3300;
        adc_command = 5'd0;
        adc_channel = 3'd0;
        adc_selected_data = 12'd0;
        adc_rising_count = 0;
        bit_count = 0;
        dac_frame_count = 0;
        serial_errors = 0;
        acceptance_start_frame = 32'h7fffffff;
        nonzero_acceptance_frames = 0;
        expected_left = 16'd0;
        expected_right = 16'd0;
        audio_cycle_count = 0;
        previous_pcm_cycle = 0;
        pcm_sample_count = 0;
        pcm_interval_errors = 0;
        spectrum_update_count = 0;
        display_update_count = 0;
        spectrum_interval_errors = 0;
        previous_spectrum_time = 0;
        minimum_spectrum_interval = 64'h7fffffffffffffff;
        maximum_spectrum_interval = 0;
        colored_pixel_seen = 1'b0;

        repeat (8) @(posedge sys_clk_50m);
        #1 rst_n = 1'b1;

        wait (audio_voice_active == 4'b1111);
        acceptance_start_frame = dac_frame_count;

        wait (dac_frame_count >= acceptance_start_frame + 2500);
        @(negedge audio_clk_12m288);
        timbre_select = 1'b1;

        wait (dac_frame_count >= acceptance_start_frame + 5000);
        @(negedge audio_clk_12m288);
        chorus_enable = 1'b1;

        wait (dac_frame_count >= acceptance_start_frame + 7500);
        @(negedge audio_clk_12m288);
        sustain_reverb_enable = 1'b1;

        wait (dac_frame_count >=
              acceptance_start_frame + REQUIRED_DAC_FRAMES);
        repeat (4) @(posedge audio_clk_12m288);

        if (serial_errors != 0) begin
            $display("FAIL: FULL 10k PT8211 protocol errors=%0d",
                     serial_errors);
            $fatal;
        end
        if (nonzero_acceptance_frames == 0) begin
            $display("FAIL: FULL 10k stream never carried nonzero audio");
            $fatal;
        end
        if ((pcm_interval_errors != 0) ||
            (pcm_sample_count < REQUIRED_DAC_FRAMES)) begin
            $display("FAIL: FULL real-time PCM samples=%0d interval_errors=%0d",
                     pcm_sample_count, pcm_interval_errors);
            $fatal;
        end
        if ((spectrum_update_count < MIN_SPECTRUM_UPDATES) ||
            (display_update_count < MIN_SPECTRUM_UPDATES) ||
            (spectrum_interval_errors != 0) || display_cdc_overrun) begin
            $display("FAIL: FULL spectrum updates=%0d display=%0d interval_errors=%0d overrun=%b",
                     spectrum_update_count, display_update_count,
                     spectrum_interval_errors, display_cdc_overrun);
            $fatal;
        end
        if (!colored_pixel_seen) begin
            $display("FAIL: FULL LCD never rendered a colored spectrum pixel");
            $fatal;
        end
        if ((timbre_blend != 9'd256) || (chorus_blend != 9'd256) ||
            (reverb_blend != 9'd256)) begin
            $display("FAIL: FULL effect switches did not settle timbre=%0d chorus=%0d reverb=%0d",
                     timbre_blend, chorus_blend, reverb_blend);
            $fatal;
        end

        $display("PASS: FULL real-time 10000-frame endurance pcm=%0d spectrum=%0d display=%0d interval_ns=%0d..%0d",
                 pcm_sample_count, spectrum_update_count,
                 display_update_count, minimum_spectrum_interval,
                 maximum_spectrum_interval);
        $finish;
    end

endmodule
