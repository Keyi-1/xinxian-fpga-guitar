`timescale 1ns/1ps
module tb_rock_voice_core;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0,off=0,sustain=0,harmony=0;
    reg [31:0] inc=0;
    reg [1:0] velocity=0;
    reg [8:0] bright=0,rock=0;
    wire valid,active,miss;
    wire signed [23:0] pcm;
    piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(off),
        .phase_inc(inc),.velocity_level(velocity),.timbre_blend(bright),.rock_blend(rock),
        .sustain_enable(sustain),.harmony_enable(harmony),.sample_valid(valid),
        .pcm_out(pcm),.active(active),.busy(),.deadline_miss(miss),.profile());
    integer f,n,count,vel_i,on_i,off_i,b_i,r_i,s_i,h_i,a_i;
    reg [31:0] inc_i;
    reg [23:0] expected;
    initial begin
        f=$fopen("rock_golden.txt","r");if(!f)$fatal(1,"FAIL: rock oracle missing");
        repeat(8)@(negedge clk);rst_n=1;
        for(n=0;n<212000;n=n+1)begin
            count=$fscanf(f,"%h %d %d %d %d %d %d %d %h %d\n",inc_i,vel_i,on_i,off_i,b_i,r_i,s_i,h_i,expected,a_i);
            if(count!=10)$fatal(1,"FAIL: rock oracle frame %0d",n);
            @(negedge clk);inc=inc_i;velocity=vel_i;on=on_i;off=off_i;
            bright=b_i;rock=r_i;sustain=s_i;harmony=h_i;ce=1;
            @(negedge clk);ce=0;
            wait(valid);#1;
            if(pcm!==expected||active!==a_i[0]||miss||$isunknown(pcm))
                $fatal(1,"FAIL: rock frame %0d got=%h expected=%h active=%b/%0d",n,pcm,expected,active,a_i);
            wait(!valid);repeat(18)@(negedge clk);
        end
        $fclose(f);
        $display("PASS: 212000 exact three-timbre samples; three complete extended dry-wah profile envelopes, six registers, four velocities, alias suppression, fifth, sustain, transitions and re-strike");
        $finish;
    end
endmodule
