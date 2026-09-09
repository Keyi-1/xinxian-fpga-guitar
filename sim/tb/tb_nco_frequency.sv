`timescale 1ns/1ps

module tb_nco_frequency;

    reg        clk;
    reg        rst_n;
    reg        sample_ce;
    reg [31:0] phase_inc;

    wire signed [15:0] sample_out;
    wire               sample_valid;

    reg [31:0] phase_inc_rom [0:35];

    integer sample_index;
    integer positive_crossings;
    reg signed [15:0] previous_sample;
    real measured_hz;

    sine_nco dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_ce   (sample_ce),
        .phase_inc   (phase_inc),
        .sample_out  (sample_out),
        .sample_valid(sample_valid)
    );

    always #1 clk = ~clk;

    initial begin
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk                = 1'b0;
        rst_n              = 1'b0;
        sample_ce          = 1'b0;
        phase_inc          = phase_inc_rom[0];
        positive_crossings = 0;
        previous_sample    = 16'sd0;

        if (^phase_inc_rom[0] === 1'bx) begin
            $display("FAIL: note_phase_inc.mem was not loaded");
            $finish;
        end

        repeat (3) @(posedge clk);
        rst_n     = 1'b1;
        sample_ce = 1'b1;

        // 丢弃第一个采样点，避免把初始零点算作过零
        @(posedge clk);
        #1;
        previous_sample = sample_out;

        for (sample_index = 1;
             sample_index < 48000;
             sample_index = sample_index + 1) begin

            @(posedge clk);
            #1;

            if (previous_sample <= 0 && sample_out > 0)
                positive_crossings = positive_crossings + 1;

            previous_sample = sample_out;
        end

        sample_ce = 1'b0;
        measured_hz = positive_crossings * 1.0;

        $display(
            "E4 positive crossings: %0d, measured frequency: %0.3f Hz",
            positive_crossings,
            measured_hz
        );

        // 允许过零计数带来约一个周期的离散误差
        if (positive_crossings < 328 ||
            positive_crossings > 331) begin
            $display("FAIL: E4 frequency outside tolerance");
            $finish;
        end

        $display("PASS: E4 frequency at 48 kHz sample rate");
        $finish;
    end

endmodule