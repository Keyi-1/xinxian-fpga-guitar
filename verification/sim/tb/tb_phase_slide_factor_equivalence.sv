`timescale 1ns/1ps
`include "guitar_config.vh"
module tb_phase_slide_factor_equivalence;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, sample_ce=0, note_on=0, voice_active=0;
    reg [31:0] target=0;
    wire [31:0] actual [0:15], reference [0:15];
    wire [15:0] actual_busy, reference_busy;
    genvar g;
    generate for (g=0;g<16;g=g+1) begin : cases
        localparam integer V = g%8;
        localparam integer N = (V==0) ? 1 : (V==1) ? 3 : (V==2) ? 8 :
                               (V==3) ? 15 : (V==4) ? 64 : (V==5) ? 960 :
                               (V==6) ? 1000 : 1024;
        localparam integer BITS = (g<8) ? 32 : 26;
        wire [31:0] case_target = (g<8) ? target : (target & 32'h03ffffff);
        phase_slide_smoother #(.SLIDE_SAMPLES(N),.PHASE_VALUE_BITS(BITS)) dut (
            .clk(clk),.rst_n(rst_n),.sample_ce(sample_ce),.note_on(note_on),
            .voice_active(voice_active),.target_phase_inc(case_target),
            .phase_inc(actual[g]),.busy(actual_busy[g])
        );
        ref_phase_slide_smoother #(.SLIDE_SAMPLES(N)) original (
            .clk(clk),.rst_n(rst_n),.sample_ce(sample_ce),.note_on(note_on),
            .voice_active(voice_active),.target_phase_inc(case_target),
            .phase_inc(reference[g]),.busy(reference_busy[g])
        );
        always @(negedge clk) if (rst_n)
            if ({actual[g],actual_busy[g]} !== {reference[g],reference_busy[g]})
                $fatal(1,"FAIL: slide divisor %0d width %0d phase/busy differs",N,BITS);
    end endgenerate
    integer cycle;
    reg [31:0] random_state=32'hac541932;
    reg [31:0] note_rom [0:35];
    integer note_index;
    initial begin
        $readmemh("../../mem/note_phase_inc.mem",note_rom);
        for (note_index=0;note_index<36;note_index=note_index+1)
            if ((note_rom[note_index] >> `NOTE_PHASE_VALUE_BITS) != 0)
                $fatal(1,"FAIL: note ROM exceeds configured exact slide value range");
        repeat(3) @(negedge clk);
        rst_n=1;sample_ce=1;
        @(negedge clk);voice_active=1;
        // Full-width up/down differences, completion, odd/power-of-two/mixed
        // divisors, and sample gating before randomized retargets/replucks.
        for (cycle=0;cycle<12000;cycle=cycle+1) begin
            @(negedge clk);
            sample_ce=(cycle%3 != 0);
            if (cycle==0) target=32'hffffffff;
            if (cycle==1800) target=0;
            if (cycle==3600) target=32'h456789ab;
            if (cycle>=5400) begin
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                if (cycle%37==0) target=random_state;
                note_on=(cycle%503==0);
                voice_active=(cycle%719 != 0);
            end
        end
        @(negedge clk);
        $display("PASS: factored/bounded slide exact to original for 8 divisors, 32/26-bit ranges, 12000 gated clocks");
        $finish;
    end
endmodule
