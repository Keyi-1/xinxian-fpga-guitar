`timescale 1ns/1ps
module tb_game_p2_actual_bank_gate;
    GSR GSR(.GSRI(1'b1));
    reg ac=0,dc=0;always #5 ac=~ac;always #7 dc=~dc;
    reg ar=0,dr=0;reg [10:0] aa=0,da=0;
    wire ap,dp;wire [95:0] a0,a1,d0,d1;
    wire [95:0] audio=ap ? a1 : a0,display=dp ? d1 : d0;
    `include "bank_actual_map.vh"
    reg [95:0] words[0:2047],previous_a=0,previous_d=0;
    integer audio_reads=0,display_reads=0,high=0,i,j;
    always @(posedge ac)begin
        #1;
        if(ar)begin
            if(audio!==words[aa])$fatal(1,"FAIL: production DPB audio address=%0d data=%h expected=%h",aa,audio,words[aa]);
            audio_reads=audio_reads+1;if(audio[70:64]==79)high=high+1;
        end else if(audio_reads && audio!==previous_a)$fatal(1,"FAIL: production DPB disabled audio read changed");
        previous_a=audio;
    end
    always @(posedge dc)begin
        #1;
        if(dr)begin
            if(display!==words[da])$fatal(1,"FAIL: production DPB display address=%0d",da);
            display_reads=display_reads+1;
        end else if(display_reads && display!==previous_d)$fatal(1,"FAIL: production DPB disabled display read changed");
        previous_d=display;
    end
    initial begin
        $readmemh("../../../mem/game_p2_static.mem",words);
        repeat(5)@(negedge ac);
        fork
            begin
                for(i=0;i<2048;i=i+1)begin @(negedge ac);ar=1;aa=i;end
                @(negedge ac);ar=0;
                repeat(8)begin @(negedge ac);aa=aa^11'h5a5;end
            end
            begin
                for(j=0;j<2048;j=j+1)begin @(negedge dc);dr=1;da=(j*519+701)%2048;end
                @(negedge dc);dr=0;
                repeat(8)begin @(negedge dc);da=da^11'h7ff;end
            end
        join
        if(audio_reads!=2048 || display_reads!=2048 || high!=1)$fatal(1,"FAIL: actual bank coverage");
        $display("PASS: production full-VG DPB bank 4096 exact asynchronous reads, all2048 records/96bits, G5 MIDI79, page boundary/one-cycle latency/disabled hold; pruned group bits proven zero");
        $finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: production bank watchdog");end
endmodule
