`timescale 1ns/1ps
module tb_piano_voice_core;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0,off=0;
    reg [1:0] velocity=0;
    reg [31:0] increment=0;
    wire [1:0] valid,active,busy,miss;
    wire signed [23:0] wet,dry;
    wire [1:0] profile0,profile1;
    piano_voice_core #(.HAMMER_ENABLE(1)) hammer (
        .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(off),
        .velocity_level(velocity),.phase_inc(increment),.sample_valid(valid[0]),
        .pcm_out(wet),.active(active[0]),.busy(busy[0]),.deadline_miss(miss[0]),.profile(profile0));
    piano_voice_core #(.HAMMER_ENABLE(0)) body (
        .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(off),
        .velocity_level(velocity),.phase_inc(increment),.sample_valid(valid[1]),
        .pcm_out(dry),.active(active[1]),.busy(busy[1]),.deadline_miss(miss[1]),.profile(profile1));
    integer file,got,j,vel_i,on_i,off_i,act_i,prof_i;
    reg signed [23:0] expected0,expected1;
    integer different=0;
    initial begin
        file=$fopen("piano_voice_golden.txt","r");
        if(!file)$fatal(1,"FAIL: generate piano oracle first");
        repeat(8)@(negedge clk);rst_n=1;
        for(j=0;j<32000;j=j+1)begin
            @(negedge clk);
            got=$fscanf(file,"%h %d %d %d %h %h %d %d\n",increment,vel_i,on_i,off_i,expected0,expected1,act_i,prof_i);
            if(got!=8)$fatal(1,"FAIL: piano golden row %0d",j);
            ce=1;velocity=vel_i;on=on_i;off=off_i;
            @(negedge clk);ce=0;on=0;off=0;
            wait(valid[0]);#1;
            if(valid!=3 || miss!=0 || busy!=0 || wet!==expected0 || dry!==expected1 ||
               active[0]!==act_i[0] || active[1]!==act_i[0] || profile0!==prof_i[1:0] || profile1!==prof_i[1:0])
                $fatal(1,"FAIL: piano sample %0d RTL=%h/%h expected=%h/%h active=%b profile=%d",j,wet,dry,expected0,expected1,active,profile0);
            if(wet!=dry)different=different+1;
            repeat(11)@(negedge clk);
        end
        if(different<1000)$fatal(1,"FAIL: missing hammer contribution");
        $fclose(file);
        $display("PASS: 32000 bit-exact piano samples; hammer on/off; velocities; profiles; slides; same-tick pluck priority; damping; rapid re-strike continuity");
        $finish;
    end
    initial begin #25000000;$fatal(1,"FAIL: piano oracle timeout");end
endmodule
