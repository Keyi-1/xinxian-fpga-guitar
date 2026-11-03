`timescale 1ns/1ps
// Behavioural properties independent of the numerical oracle: fresh strikes,
// reproducible reset, bounded states, a smooth retired tail and zero ROM replay.
module tb_procedural_hammer_properties;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0;
    reg [31:0] inc=32'd23409859;
    wire valid,miss;
    piano_voice_core dut(.clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(1'b0),
        .velocity_level(2'd3),.phase_inc(inc),.timbre_blend(9'd0),.rock_blend(9'd0),
        .sustain_enable(1'b0),.harmony_enable(1'b0),.sample_valid(valid),.pcm_out(),
        .active(),.busy(),.deadline_miss(miss),.profile());
    reg signed [15:0] first_attack[0:2047];
    integer k,b,changed=0;
    reg [31:0] saved_random;
    task step(input bit strike);
        @(negedge clk);ce=1;on=strike;
        @(negedge clk);ce=0;on=0;
        wait(valid);#1;
        if(miss || $isunknown(dut.hammer_value) || dut.hammer_value>2048 || dut.hammer_value< -2048)
            $fatal(1,"FAIL: procedural bounds/deadline/unknown");
        for(b=0;b<3;b=b+1)begin
            if(dut.procedural_hammer.u_hammer.y1[b]==18'sd131071 ||
               dut.procedural_hammer.u_hammer.y1[b]==-18'sd131072)
                $fatal(1,"FAIL: unintended internal filter clipping");
        end
        if(dut.frame_age>=2032 && dut.frame_age<2048 &&
           (dut.hammer_value>2 || dut.hammer_value< -2))
            $fatal(1,"FAIL: audible step at end of transient");
        if(dut.frame_age>=2048 && dut.hammer_value!=0)
            $fatal(1,"FAIL: transient did not retire");
        repeat(11)@(negedge clk);
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        for(k=0;k<2400;k=k+1)begin
            step(k==0);
            if(k<2048)first_attack[k]=dut.hammer_value;
        end
        saved_random=dut.procedural_hammer.u_hammer.random_state;
        for(k=0;k<2400;k=k+1)begin
            step(k==0);
            if(k<2048 && first_attack[k]!=dut.hammer_value)changed=changed+1;
        end
        if(changed<1000 || saved_random==dut.procedural_hammer.u_hammer.random_state)
            $fatal(1,"FAIL: repeated frozen hammer sequence");
        @(negedge clk);rst_n=0;repeat(8)@(negedge clk);rst_n=1;
        for(k=0;k<2400;k=k+1)begin
            step(k==0);
            if(k<2048 && first_attack[k]!==dut.hammer_value)
                $fatal(1,"FAIL: reset is not reproducible, sample %0d",k);
        end
        inc=32'd29494323;
        for(k=0;k<2400;k=k+1)step(k==0);
        inc=32'd35075240;
        for(k=0;k<2400;k=k+1)step(k==0);
        $display("PASS: fresh procedural strikes; reset reproduces arithmetic; no internal clipping; last 16 samples <= 2 PCM16 units; exact zero after 2048 samples");
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: procedural property timeout");end
endmodule
