`timescale 1ns/1ps
module tb_game_p2_layout_gate;
    GSR GSR(.GSRI(1'b1));
    `include "p2_gate_pair.vh"
    reg [2:0] test_page=5,test_selected=0;
    reg [255:0] test_snapshot=0;
    reg [399:0] test_visual=0;reg [159:0] test_targets=0;
    reg test_update=0,manual_frame=0;
    wire [383:0] g_centres;wire [287:0] g_tails;wire [31:0] g_blocks;
    wire g_overflow,g_deadline;
    `include "chart_outputs.vh"
    reg [95:0] words[0:2047];
    integer bases[0:3],counts[0:3],s,e,j,head,now,passes=0;
    initial begin
        `include "stage_force.vh"
        force gate.u_display.u_scan.frame_start=manual_frame;
        force reference.u_display.u_scan.frame_start=manual_frame;
    end
    task publish(input integer song,time_value,first,input [63:0] consumed);
        @(negedge sys_clk);test_snapshot=0;test_snapshot[63:0]=consumed;test_snapshot[95:64]=time_value;
        test_snapshot[229:228]=2;test_snapshot[237:235]=song;
        test_snapshot[249:238]=first;test_snapshot[255:250]=song+1;
        manual_frame=1;@(negedge sys_clk);manual_frame=0;test_update=1;
        @(negedge sys_clk);test_update=0;repeat(1600)@(negedge sys_clk);
        if(reference.u_display.p2.u_chart.state!=0 || g_overflow || g_deadline)$fatal(1,"FAIL: synthesized layout deadline/capacity");
        if(g_blocks!==reference.u_display.valid_blocks)$fatal(1,"FAIL: synthesized block visibility song=%0d t=%0d",song,time_value);
        for(j=0;j<32;j=j+1)if(g_blocks[j])begin
            if(g_centres[j*12+:12]!==reference.u_display.centres[j*12+:12] || g_tails[j*9+:9]!==reference.u_display.tails[j*9+:9])
                $fatal(1,"FAIL: synthesized coordinate/tail song=%0d t=%0d lane-slot=%0d",song,time_value,j);
        end
        passes=passes+1;
    endtask
    initial begin
        $readmemh("../../../mem/game_p2_static.mem",words);
        bases[0]=0;bases[1]=67;bases[2]=323;bases[3]=491;
        counts[0]=67;counts[1]=256;counts[2]=168;counts[3]=128;
        wait(reference.lcd_rst_n);repeat(10)@(negedge audio_clk);audio_run=0;
        for(s=0;s<4;s=s+1)begin
            publish(s,-96000,0,0);publish(s,-48000,0,0);
            for(e=0;e<counts[s];e=e+1)begin
                now=words[bases[s]+e][31:0];head=e>2 ? e-2 : 0;
                publish(s,now-7200,head,0);publish(s,now,head,0);
                publish(s,now+7201,head,64'ha55aa55aa55aa55a);
            end
            $display("Progress: synthesized complete song %0d layouts matched (%0d passes)",s,passes);
        end
        $display("PASS: synthesized P2 actual shared-ROM wiring and %0d consecutive layouts, all 619 production events, ring heads, consumption and countdown boundaries match RTL",passes);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: layout gate watchdog");end
endmodule
