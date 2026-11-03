`timescale 1ns/1ps

module tb_audio_sample_tick;

    reg clk_audio_ref;
    reg rst_n;
    reg previous_sample_tick;

    wire sample_tick;
    wire sample_valid;
    wire signed [15:0] sample_out;

    reg [31:0] phase_inc_rom [0:35];
    reg [31:0] phase_inc;

    integer cycle_count;
    integer tick_count;
    integer cycles_since_tick;

    sample_tick_gen tick_gen (
        .clk_audio_ref(clk_audio_ref),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick)
    );

    sine_nco nco (
        .clk         (clk_audio_ref),
        .rst_n       (rst_n),
        .sample_ce   (sample_tick),
        .phase_inc   (phase_inc),
        .sample_out  (sample_out),
        .sample_valid(sample_valid)
    );

    always #1 clk_audio_ref = ~clk_audio_ref;

    initial begin
        $readmemh("../../mem/note_phase_inc.mem", phase_inc_rom);

        clk_audio_ref   = 1'b0;
        rst_n           = 1'b0;
	previous_sample_tick = 1'b0;
        phase_inc       = phase_inc_rom[0];

        cycle_count     = 0;
        tick_count      = 0;
        cycles_since_tick = 0;

        repeat (3) @(posedge clk_audio_ref);
        rst_n = 1'b1;

        while (tick_count < 3) begin
            @(posedge clk_audio_ref);
            #1;

            cycle_count      = cycle_count + 1;
            cycles_since_tick = cycles_since_tick + 1;

	// NCO 的输出有效信号对应上一拍的 sample_tick
	if (sample_valid !== previous_sample_tick) begin
    	$display(
        	"FAIL: sample_valid alignment, previous_tick=%b valid=%b",
        	previous_sample_tick,
        	sample_valid
    	);
    	$finish;
	end

	if (sample_tick) begin
    	if (tick_count > 0 &&
        	cycles_since_tick != 256) begin
        	$display(
            	"FAIL: sample tick interval=%0d",
            	cycles_since_tick
        	);
        	$finish;
    end

    tick_count        = tick_count + 1;
    cycles_since_tick = 0;
end

previous_sample_tick = sample_tick;        end

@(posedge clk_audio_ref);
#1;

if (sample_valid !== previous_sample_tick) begin
    $display("FAIL: final sample_valid alignment");
    $finish;
end

        $display(
            "PASS: 12.288 MHz to 48 kHz sample tick, ticks=%0d",
            tick_count
        );
        $finish;
    end

endmodule