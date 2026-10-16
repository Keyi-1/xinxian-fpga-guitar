`timescale 1ns/1ps
// Seek the architectural elapsed register to each real event; all ROM reads,
// DDS decoding, launches, router and audio logic use the actual full VG.
module tb_game_p2_melody_seek_gate;
    GSR GSR(.GSRI(1'b1));
    `include "p2_gate_pair.vh"
    reg [4:0] inject_command=0;reg inject_valid=0;
    reg [24:0] seek_time=0;
    wire [127:0] g_phase;
    reg [95:0] words[0:2047];
    integer e,lane,midi,high=0,cycles=0;
    initial begin
        `include "engine_force.vh"
    end
    `include "seek_actual_map.vh"
    function automatic [31:0] increment(input integer note);
        real hz;
        begin hz=440.0*(2.0**((note-69)/12.0));increment=$rtoi(hz*4294967296.0/48000.0+0.5);end
    endfunction
    always @(posedge audio_clk)begin
        #2;
        if(reference.audio_rst_n)begin
            cycles=cycles+1;
            if(gaudio!==raudio || g_phase!==`RCORE.target_phase ||
                `GCORE.launch!==`RCORE.launch || `GCORE.fault_Z!==`RCORE.fault)
                $fatal(1,"FAIL: actual melody seek differs event=%0d time=%0d",e,seek_time);
        end
    end
    initial begin
        $readmemh("../../../mem/game_p2_static.mem",words);
        wait(reference.lcd_rst_n);repeat(10)@(negedge sys_clk);sys_run=0;
        @(negedge audio_clk);inject_command={3'd3,2'd3};inject_valid=1;
        wait(reference.dst_command_ack);@(negedge audio_clk);inject_valid=0;
        wait(`RCORE.countdown);
        // The generator proves elapsed[24:0] are actual DFF Q nodes. No
        // derived predecode or DDS/ROM/launch result is forced in this test.
        force `RCORE.elapsed=seek_time;force `GCORE.elapsed=seek_time;
        force `RCORE.countdown_left=32'd1;force `GCORE.countdown_left=32'd1;
        @(posedge audio_clk);while(!reference.u_audio.sample_tick)@(posedge audio_clk);
        #3;release `RCORE.countdown_left;release `GCORE.countdown_left;
        for(e=0;e<212;e=e+1)begin
            @(negedge audio_clk);seek_time=words[491+e][24:0];
            while(!reference.u_audio.sample_tick)@(negedge audio_clk);
            @(posedge audio_clk);repeat(180)@(posedge audio_clk);#3;
            lane=words[491+e][72:71];midi=words[491+e][70:64];
            if(`RCORE.launch!==(4'b1<<lane) || `GCORE.launch!==(4'b1<<lane) ||
                g_phase[lane*32+:32]!==increment(midi) || `RCORE.fault || `RCORE.deadline_miss)
                $fatal(1,"FAIL: actual ROM/DDS/launch event=%0d MIDI=%0d phase=%h expected=%h",e,midi,g_phase[lane*32+:32],increment(midi));
            if(midi==79)begin high=high+1;if(!g_phase[lane*32+26])$fatal(1,"FAIL: real G5 decoder lost bit26");end
        end
        if(high!=1)$fatal(1,"FAIL: actual melody seek G5 coverage");
        $display("PASS: actual full-VG melody 212 real-ROM attacks/precise DDS including G5 bit26, ring wraps, controller launch and musical PT8211/I2S exact; %0d clocks; seek at proven elapsed DFF Q only, not wall-clock playback",cycles);
        $finish;
    end
    initial begin #300000000;$fatal(1,"FAIL: actual melody seek watchdog");end
endmodule
