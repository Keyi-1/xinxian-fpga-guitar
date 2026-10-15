`timescale 1ns/1ps
module tb_game_p2_judgement;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,demo=0,enable=1;
    reg [6:0] divider=0;
    always @(posedge clk)divider<=!rst_n ? 0 : divider+1'b1;
    wire tick=divider==127;
    reg [3:0] pluck=0;
    reg [95:0] memory[0:7],data;
    wire rd;wire [10:0] address;
    always @(posedge clk)if(rd)data<=memory[address];
    wire [3:0] on,off;
    wire [127:0] tuning;
    wire [7:0] velocity;
    wire [31:0] time_now,score;
    wire [15:0] hits,misses,wrongs,combo,max_combo;
    wire [11:0] judgement,head;
    wire [7:0] epoch;
    wire fault,deadline,finished,miss_event;
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(0),.PERFECT_SAMPLES(3),.GOOD_SAMPLES(9),
        .WINDOW_SAMPLES(15),.DISPLAY_AHEAD_SAMPLES(100)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable),.start_song(start),.demo(demo),
        .catalog_valid(1'b1),.catalog_base(11'd0),.catalog_count(12'd8),.catalog_duration(32'd400),
        .pluck_valid(pluck),.velocity(8'he4),.read_enable(rd),.read_address(address),.read_data(data),
        .note_on(on),.note_off(off),.target_phase(tuning),.note_velocity(velocity),.song_time(time_now),
        .countdown(),.finished(finished),.fault(fault),.fault_code(),.deadline_miss(deadline),
        .score(score),.combo(combo),.max_combo(max_combo),.hits(hits),.misses(misses),.wrongs(wrongs),
        .judgement(judgement),.judgement_epoch(epoch),.window_head(head),.window_count(),.consumed_snapshot(),
        .generation(),.miss_event(miss_event),.snapshot_valid());
    function automatic [25:0] midi_phase(input [6:0] midi);
        `include "../config/game_p2_phase.vh"
    endfunction
    task automatic put(input integer n,t,l,m);
        memory[n]=96'(t)|(96'd20<<32)|(96'(m)<<64)|(96'(l)<<71)|(96'd2<<73);
    endtask
    task automatic begin_song;
        @(negedge clk);start=1;@(negedge clk);start=0;
    endtask
    task automatic strike(input integer t,input [3:0] mask);
        wait(time_now==t);@(negedge clk);pluck=mask;@(negedge clk);pluck=0;
    endtask
    task automatic check(input bit pass,input string detail);
        if(!pass)$fatal(1,"FAIL: %s t=%0d score=%0d hits=%0d miss=%0d wrong=%0d",detail,time_now,score,hits,misses,wrongs);
    endtask
    integer launches=0,chords=0,cues=0,i,last_launch[0:3];
    always @(posedge clk)if(rst_n)begin
        if(miss_event)begin
            if(demo)$fatal(1,"FAIL: preview Miss cue");
            cues=cues+1;
        end
        if(tick)begin
            launches=launches+$countones(on);if(on==15)chords=chords+1;
            for(i=0;i<4;i=i+1)begin
                if(on[i])last_launch[i]=time_now;
                if(off[i] && time_now-last_launch[i]!=20)$fatal(1,"FAIL: stale note-off truncated a new strike");
            end
            if(fault || deadline)$fatal(1,"FAIL: ordinary judgement fault/deadline");
        end
    end
    initial begin
        put(0,50,0,64);put(1,52,1,59);put(2,100,2,55);put(3,200,3,50);
        for(i=4;i<8;i=i+1)put(i,300,i-4,64-(i-4)*2);
        repeat(5)@(negedge clk);rst_n=1;begin_song();
        strike(20,2);wait(time_now==22);
        check(wrongs==1 && hits==0 && tuning[63:32]==midi_phase(59),"Wrong selects future candidate without consuming");
        strike(49,3);wait(time_now==51);
        check(score==200 && hits==2 && velocity[3:0]==4'h4,"two-lane Perfect and real velocity");
        strike(92,4);wait(time_now==94);check(score==270 && hits==3,"Good window");
        strike(184,8);wait(time_now==186);check(hits==3 && wrongs==2,"outside Bad window remains Wrong");
        strike(201,8);wait(time_now==203);check(score==370 && hits==4,"Wrong does not consume later hit");
        strike(285,15);wait(time_now==287);
        check(score==470 && hits==8 && combo==0,"inclusive four-lane Bad boundary");
        wait(finished);check(misses==0 && max_combo==3 && head==8 && cues==0,"all hits retire once");
        begin_song();wait(finished);check(misses==8 && hits==0 && score==0 && cues==5,"silent misses once per batch");
        @(negedge clk);demo=1;launches=0;chords=0;begin_song();wait(finished);
        check(launches==8 && chords==1 && score==0 && hits==0 && epoch==0,"explicit preview, simultaneous four-lane chord, no scoring");
        check(dut.add16(16'hfffe,7'd4)==16'hffff && dut.add16(16'd300,7'd4)==16'd304,"counter saturation boundary");
        $display("PASS: P2 Perfect/Good/Bad boundaries, Wrong non-consumption, four-lane chords/velocity, release, Miss cues, saturation and preview separation");
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: P2 judgement timeout");end
endmodule
