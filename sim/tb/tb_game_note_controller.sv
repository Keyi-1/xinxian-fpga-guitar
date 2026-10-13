`timescale 1ns/1ps
module tb_game_note_controller;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,start_song=0,demo=0;
    reg [3:0] pluck=0;reg [7:0] velocity=8'he4;
    reg [6:0] divider=0;
    wire tick=divider==127;
    always @(posedge clk)divider<=!rst_n ? 0 : divider+1'b1;
    wire [3:0] on,off;
    wire [127:0] phase,consumed;
    wire [7:0] note_velocity,combo,max_combo,hits,misses,wrongs;
    wire [31:0] time_now;
    wire [19:0] score;
    wire [11:0] judgement;
    wire countdown,finished,deadline;
    game_note_controller #(.EVENT_COUNT(8),.DURATION_SAMPLES(400),.COUNTDOWN_SAMPLES(0),
        .PERFECT_SAMPLES(3),.GOOD_SAMPLES(9),.WINDOW_SAMPLES(15)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable),.start_song(start_song),.demo(demo),
        .pluck_valid(pluck),.velocity(velocity),.note_on(on),.note_off(off),.target_phase(phase),.note_velocity(note_velocity),
        .song_time(time_now),.countdown(countdown),.finished(finished),.score(score),.combo(combo),.max_combo(max_combo),
        .hits(hits),.misses(misses),.wrongs(wrongs),.judgement(judgement),.consumed(consumed),.deadline_miss(deadline));
    task event_at(input integer index,t,d,l,p);
        dut.u_rom.memory[index]=(80'(l)<<74)|(80'(p)<<48)|(80'(d)<<24)|80'(t);
    endtask
    task start;
        @(negedge clk);start_song=1;@(negedge clk);start_song=0;
    endtask
    task strike(input integer t,input [3:0] mask);
        wait(time_now==t);@(negedge clk);pluck=mask;@(negedge clk);pluck=0;
    endtask
    task check(input bit pass,input string detail);
        if(!pass)$fatal(1,"FAIL: %s t=%0d score=%0d hits=%0d miss=%0d wrong=%0d",detail,time_now,score,hits,misses,wrongs);
    endtask
    integer launches=0,chords=0,last_launch[0:3],lane_index;
    always @(posedge clk)if(rst_n && tick)begin
        if(on!=0)launches=launches+$countones(on);
        if(on==15)chords=chords+1;
        for(lane_index=0;lane_index<4;lane_index=lane_index+1)begin
            if(on[lane_index])last_launch[lane_index]=time_now;
            if(off[lane_index] && time_now-last_launch[lane_index]!=20)
                $fatal(1,"FAIL: score duration/restrike release lane=%0d",lane_index);
        end
        if(deadline)$fatal(1,"FAIL: controller exceeded sample budget");
    end
    initial begin
        #1;
        event_at(0,50,20,0,1001);event_at(1,52,20,1,2001);
        event_at(2,100,20,2,3001);event_at(3,200,20,3,4001);
        event_at(4,300,20,0,1002);event_at(5,300,20,1,2002);
        event_at(6,300,20,2,3002);event_at(7,300,20,3,4002);
        repeat(5)@(negedge clk);rst_n=1;start();
        strike(20,2);wait(time_now==22);
        check(wrongs==1 && consumed==0 && phase[63:32]==2001,"early wrong feedback must not consume or shift score");
        strike(49,3);wait(time_now==51);
        check(score==200 && hits==2 && consumed[1:0]==3,"two simultaneous lanes, inclusive perfect boundary");
        check(note_velocity[3:0]==velocity[3:0],"actual velocity is latched per lane");
        strike(92,4);wait(time_now==94);check(score==270 && hits==3,"Good window");
        strike(184,8);wait(time_now==186);check(!consumed[3] && wrongs==2,"outside window never consumes upcoming note");
        strike(201,8);wait(time_now==203);check(score==370 && hits==4,"future event still hittable after wrong strike");
        strike(285,15);wait(time_now==287);
        check(score==470 && hits==8 && combo==0 && consumed[7:0]==255,"four-tone Bad boundary, independent consumption");
        check(phase=={32'd4002,32'd3002,32'd2002,32'd1002},"score supplies DDS, not fret/open pitch");
        wait(finished);check(misses==0 && max_combo==3,"hit events do not Miss; wrong strike breaks combo");
        start();wait(finished);check(score==0 && hits==0 && misses==8,"silent player misses every event exactly once");
        @(negedge clk);demo=1;launches=0;chords=0;start();wait(finished);
        check(launches==8 && chords==1 && consumed[7:0]==255,"explicit preview plays full score once, including chord");
        check(score==0 && hits==0 && wrongs==0,"preview is not a scored/autoplay game");
        $display("PASS: game nearest-event windows, velocity, wrong non-consumption, four-note chord, release, Miss and restart/preview");$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: game watchdog");end
endmodule
