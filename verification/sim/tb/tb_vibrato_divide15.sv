`timescale 1ns/1ps
module tb_vibrato_divide15;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,note=0,active=0;
    reg [31:0] target=0;
    wire [31:0] phase[0:4],old_phase[0:4];wire [4:0] busy,old_busy;
    integer cases22=0,wide_cases=0,clocks=0,n;
    reg [63:0] random_state=64'h279a40bd201b9ee3;
    reg [26:0] number27;reg [32:0] number33;
    function [63:0] random_next(input [63:0] value);
        reg [63:0] z;begin z=value^(value<<13);z=z^(z>>7);random_next=z^(z<<17);end
    endfunction
    genvar g;
    generate for(g=0;g<5;g=g+1)begin:pair
        localparam BITS=g==0 ? 26 : g==1 ? 27 : 32;
        localparam SLIDE=g==3 ? 15 : g==4 ? 997 : 960;
`define PORTS .clk(clk),.rst_n(rst_n),.sample_ce(tick),.note_on(note),.voice_active(active),.target_phase_inc(target)
        vibrato_div15_phase_slide_smoother #(.PHASE_VALUE_BITS(BITS),.SLIDE_SAMPLES(SLIDE)) dut(`PORTS,.phase_inc(phase[g]),.busy(busy[g]));
        vibrato_before_phase_slide_smoother #(.PHASE_VALUE_BITS(BITS),.SLIDE_SAMPLES(SLIDE)) frozen(`PORTS,.phase_inc(old_phase[g]),.busy(old_busy[g]));
`undef PORTS
        always @(posedge clk)begin
            #1;
            if(rst_n && {phase[g],busy[g],dut.step_size} !== {old_phase[g],old_busy[g],frozen.step_size})
                $fatal(1,"FAIL: exact slide output/state pair%0d cycle%0d",g,clocks);
        end
    end endgenerate
    initial begin
        // Exhaust every22-bit reduced numerator, a superset of the complete
        // production27-bit DDS difference+ceil input domain.
        for(n=0;n<4194304;n=n+1)begin
            if(pair[1].dut.divide15_exact(22'(n))!==22'(n/15))$fatal(1,"FAIL: exhaustive22 /15 n%0d",n);
            cases22=cases22+1;
        end
        for(n=0;n<200000;n=n+1)begin
            random_state=random_next(random_state);
            number27=random_state[26:0];number33={random_state[47],random_state[31:0]};
            if(n<1024)number33=33'h1ffffffff-n;
            if(pair[2].dut.divide15_exact(number27)!==number27/27'd15 ||
               pair[3].dut.divide15_exact(number33)!==number33/33'd15)
                $fatal(1,"FAIL: wide bounded /15");
            wide_cases=wide_cases+2;
        end
        repeat(4)@(negedge clk);rst_n=1;
        for(n=0;n<120000;n=n+1)begin
            @(negedge clk);clocks=clocks+1;random_state=random_next(random_state);
            tick=n%7==0;note=random_state[7:0]==0;
            if(n%137==0)target=random_state[31:0];
            if(n%991==0)active=~active;
            rst_n=n%4096!=0;
        end
        repeat(4)@(negedge clk);
        $display("PASS: exact /15 %0d exhaustive22 +%0d wide27/33-bit quotients; %0d dynamic clocks/five phase26/27/32 widths and slide960/15/997 pairs, output/step/busy identical every clock, note/active/reset/retarget boundaries, no new sample latency",cases22,wide_cases,clocks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: divider/slide watchdog");end
endmodule
