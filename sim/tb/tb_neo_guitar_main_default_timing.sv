`timescale 1ns/1ps
// Smoke test with EVERY hardware parameter left at its shipped default.
module tb_neo_guitar_main_default_timing;
    reg clk = 0;
    always #40.690104 clk = ~clk; // 12.288 MHz
    reg rst_n = 0;
    reg [31:0] pressed = 32'h00_00_00_01;
    tri ROW0, ROW1, ROW2, ROW3;
    wire [7:0] cols = (ROW0 === 0) ? ~pressed[7:0] :
                      (ROW1 === 0) ? ~pressed[15:8] :
                      (ROW2 === 0) ? ~pressed[23:16] :
                      (ROW3 === 0) ? ~pressed[31:24] : 8'hff;
    wire cs_n, sclk, mosi, bclk, lrck, din, pa;
    reg miso = 0;
    wire [3:0] leds;
    reg [11:0] adc_code [0:3];
    neo_guitar_main_top dut (
        .audio_clk_12m288(clk), .rst_n(rst_n),
        .ROW0(ROW0), .ROW1(ROW1), .ROW2(ROW2), .ROW3(ROW3),
        .COL0(cols[0]), .COL1(cols[1]), .COL2(cols[2]), .COL3(cols[3]),
        .COL4(cols[4]), .COL5(cols[5]), .COL6(cols[6]), .COL7(cols[7]),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_mosi(mosi), .adc_miso(miso),
        .dac_bclk(bclk), .dac_lrck(lrck), .dac_din(din),
        .pa_en_n(pa), .event_led(leds)
    );
    integer rises = 0;
    reg [4:0] command = 0;
    reg [11:0] conversion = 0;
    always @(negedge cs_n) begin rises = 0; command = 0; miso = 0; end
    always @(posedge sclk) if (!cs_n) begin
        rises = rises + 1;
        if (rises <= 5) command = {command[3:0], mosi};
        if (rises == 5) conversion = adc_code[command[1:0]];
    end
    always @(negedge sclk) if (!cs_n) begin
        if (rises >= 7 && rises <= 18) miso = conversion[18-rises];
        else miso = 0;
    end
    task check(input bit ok, input string message);
        if (!ok) $fatal(1, "FAIL: %s", message);
    endtask
    integer note_count = 0, off_count = 0;
    integer cycles = 0, last_tick = 0, observed_ticks = 0;
    real excursion_time, attack_time;
    always @(posedge clk) if (dut.u_audio.audio_rst_n) begin
        cycles = cycles + 1;
        if (dut.u_audio.u_board_audio_chain.sample_tick) begin
            if (observed_ticks != 0)
                check(cycles-last_tick == 256, "default audio tick divider");
            observed_ticks = observed_ticks + 1;
            last_tick = cycles;
        end
        if (dut.u_audio.u_board_audio_chain.note_on[0]) begin
            note_count = note_count + 1;
            attack_time = $realtime;
        end
        if (dut.u_audio.u_board_audio_chain.note_off[0]) off_count = off_count + 1;
    end
    real last_bclk = 0;
    always @(posedge bclk) if (dut.u_audio.audio_rst_n) begin
        if (last_bclk != 0)
            check($realtime-last_bclk > 651.03 && $realtime-last_bclk < 651.05,
                  "default PT8211 BCLK is 1.536 MHz");
        last_bclk = $realtime;
    end
    integer j;
    initial begin
        for (j = 0; j < 4; j = j + 1) adc_code[j] = 2053;
        repeat (8) @(negedge clk);
        rst_n = 1;
        #6500000; // Includes default 1 ms matrix frames and five-frame debounce.
        check(dut.u_audio.stable_fret_id == 1 && note_count == 0 && dut.u_audio.u_board_audio_chain.voice_active == 0,
              "default matrix selects F4 silently");
        @(negedge clk);
        excursion_time = $realtime;
        adc_code[0] = 2253;
        wait (note_count == 1);
        check(attack_time-excursion_time < 100000,
              "default digital ADC-excursion-to-Attack delay below 100 us");
        repeat (100) @(negedge clk);
        check(dut.u_audio.u_board_audio_chain.phase_inc[31:0] == 32'h01DCD01D, "default F4 phase increment");
        #2500000;
        check(dut.u_audio.u_board_audio_chain.g_piano.u_core.voice[0].u_voice.age > 0 &&
              dut.u_audio.u_board_audio_chain.deadline_miss == 0 &&
              dut.u_audio.u_board_audio_chain.voice_active == 1 && pa == 0, "default piano voice, cadence and PA");
        $display("PASS: shipped defaults select silently; Fs=48 kHz; PT8211 BCLK=1.536 MHz; ADC excursion to Attack=%0.3f us", (attack_time-excursion_time)/1000.0);
        pressed = 0;
        #6500000;
        check(off_count == 1 && dut.u_audio.u_board_audio_chain.smoothed_phase_inc[31:0] == 32'h01DCD01D,
              "default Release holds F4 rather than jumping to open E4");
        check(note_count == 1, "held ADC excursion cannot retrigger default detector");
        $display("PASS: shipped-default debounce, Attack and final-fret Release");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "FAIL: default-timing smoke timeout");
    end
endmodule
