`timescale 1ns/1ps
// Component injection at registered controller outputs; complete production
// router, widened smoother, all piano/effect logic and serial outputs remain.
module tb_game_p2_range_gate;
    GSR GSR(.GSRI(1'b1));
    `include "p2_gate_pair.vh"
    reg [4:0] inject_command=0;reg inject_valid=0;
    reg [127:0] inject_phase;reg [3:0] inject_launch=0;
    wire [127:0] g_audible;
    `include "range_actual_observe.vh"
    integer samples=0,cycles=0,nonzero=0,origin;
    initial begin
        `include "engine_force.vh"
        `include "range_actual_force.vh"
    end
    function automatic [31:0] increment(input integer midi);
        real hz;
        begin hz=440.0*(2.0**((midi-69)/12.0));increment=$rtoi(hz*4294967296.0/48000.0+0.5);end
    endfunction
    always @(posedge audio_clk)begin
        #2;
        if(reference.audio_rst_n)begin
            cycles=cycles+1;
            if(gaudio!==raudio || g_audible!==reference.u_audio.audible_phase)
                $fatal(1,"FAIL: actual G5 audio/phase differs sample=%0d phase=%h/%h",samples,g_audible,reference.u_audio.audible_phase);
            if(reference.u_audio.sample_tick)samples=samples+1;
            if(gaudio[2] || gaudio[6])nonzero=nonzero+1;
        end
    end
    task wait_samples(input integer count);
        integer goal;
        begin goal=samples+count;wait(samples>=goal);@(negedge audio_clk);end
    endtask
    initial begin
        inject_phase={increment(50),increment(72),increment(78),increment(79)};
        wait(reference.lcd_rst_n);repeat(10)@(negedge sys_clk);space_key=0;sys_run=0;
        @(negedge audio_clk);inject_command={3'd3,2'd3};inject_valid=1;
        wait(reference.dst_command_ack);@(negedge audio_clk);inject_valid=0;
        wait(`RCORE.countdown);
        force `RCORE.countdown_left=32'd1;force `GCORE.countdown_left=32'd1;
        @(posedge audio_clk);while(!reference.u_audio.sample_tick)@(posedge audio_clk);
        #3;release `RCORE.countdown_left;release `GCORE.countdown_left;
        wait_samples(1100);
        @(negedge audio_clk);while(!reference.u_audio.sample_tick)@(negedge audio_clk);
        inject_launch=15;@(negedge audio_clk);inject_launch=0;
        wait_samples(128);
        if(g_audible[31:0]!==increment(79) || !g_audible[26])$fatal(1,"FAIL: synthesized G5 held phase truncated");
        inject_phase[31:0]=increment(50);wait_samples(1100);
        if(g_audible[31:0]!==increment(50))$fatal(1,"FAIL: synthesized down-slide endpoint");
        inject_phase[31:0]=increment(79);wait_samples(1100);
        if(g_audible[31:0]!==increment(79) || nonzero==0)$fatal(1,"FAIL: synthesized up-slide/nonzero");
        @(negedge audio_clk);inject_command=0;inject_valid=1;
        wait(reference.dst_command_ack);@(negedge audio_clk);inject_valid=0;
        if(reference.u_audio.active!=0)$fatal(1,"FAIL: synthesized extended sustain release");
        $display("PASS: actual full-VG D3-G5 audio component %0d clocks/%0d samples; architectural controller-output injection, second timbre, G5 bit26 held, bidirectional slides, sustained exit and musical PT8211/I2S exact",cycles,samples);
        $finish;
    end
    initial begin #300000000;$fatal(1,"FAIL: range gate watchdog samples=%0d",samples);end
endmodule
