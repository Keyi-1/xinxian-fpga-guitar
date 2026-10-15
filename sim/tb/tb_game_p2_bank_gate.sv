`timescale 1ns/1ps
module tb_game_p2_bank_gate;
    GSR GSR(.GSRI(1'b1));
    reg ac=0,dc=0;always #5 ac=~ac;always #7 dc=~dc;
    reg ar=0,dr=0;reg [10:0] aa=0,da=0;
    wire [95:0] ga,gd,ra,rd;reg [95:0] words[0:2047],last_a,last_d;
    integer ai,di,reads_a=0,reads_d=0;
    `define BANK .audio_clk(ac),.audio_read(ar),.audio_address(aa),.display_clk(dc),.display_read(dr),.display_address(da)
    game_p2_score_bank gate(`BANK,.audio_data(ga),.display_data(gd));
    rtlref_game_p2_score_bank reference(`BANK,.audio_data(ra),.display_data(rd));
    initial $readmemh("../../../mem/game_p2_static.mem",words);
    always @(posedge ac)begin
        #1;
        if(ar)begin
            if(ga!==words[aa] || ra!==words[aa])$fatal(1,"FAIL: one-clock audio ROM addr=%d gate=%h RTL=%h expected=%h",aa,ga,ra,words[aa]);
            reads_a=reads_a+1;
        end else if(reads_a!=0 && (ga!==last_a || ra!==last_a))$fatal(1,"FAIL: disabled audio read changed");
        last_a=ga;
    end
    always @(posedge dc)begin
        #1;
        if(dr)begin
            if(gd!==words[da] || rd!==words[da])$fatal(1,"FAIL: one-clock display ROM addr=%d gate=%h RTL=%h expected=%h",da,gd,rd,words[da]);
            reads_d=reads_d+1;
        end else if(reads_d!=0 && (gd!==last_d || rd!==last_d))$fatal(1,"FAIL: disabled display read changed");
        last_d=gd;
    end
    initial begin
        repeat(4)@(negedge ac);
        fork
            begin
                for(ai=0;ai<2048;ai=ai+1)begin @(negedge ac);ar=1;aa=ai;end
                @(negedge ac);ar=0;
                repeat(32)begin @(negedge ac);aa=aa+73;end
            end
            begin
                for(di=0;di<2048;di=di+1)begin @(negedge dc);dr=1;da=(di*137+17)%2048;end
                @(negedge dc);dr=0;
                repeat(32)begin @(negedge dc);da=da+91;end
            end
        join
        if(reads_a!=2048 || reads_d!=2048)$fatal(1,"FAIL: missing ROM addresses");
        $display("PASS: synthesized explicit DPB ROM all 2048 x 96-bit records on both asynchronous ports, 4096 exact reads, page boundary, one-clock latency and disabled-read hold");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: bank gate watchdog");end
endmodule
