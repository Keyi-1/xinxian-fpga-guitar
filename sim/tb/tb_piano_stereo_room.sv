`timescale 1ns/1ps
module tb_piano_stereo_room;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid_in=0;
    reg signed [23:0] left=0,right=0;
    wire valid;
    wire signed [23:0] out_l,out_r;
    piano_stereo_room #(.DELAY_A(7),.DELAY_B(11),.DELAY_C(17)) dut (
        .clk(clk),.rst_n(rst_n),.sample_valid_in(valid_in),.left_in(left),.right_in(right),
        .sample_valid(valid),.left_out(out_l),.right_out(out_r));
    integer k,tail=0,different=0;
    task step(input integer x);
        @(negedge clk);left=x;right=x;valid_in=1;
        @(negedge clk);valid_in=0;
        wait(valid);#1;
        if($isunknown({out_l,out_r}))$fatal(1,"FAIL: room read uninitialized RAM");
        if(out_l!=0||out_r!=0)tail=tail+1;
        if(out_l!=out_r)different=different+1;
        repeat(2)@(negedge clk);
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(k=0;k<20;k=k+1)begin
            step(0);
            if(out_l!=0||out_r!=0)$fatal(1,"FAIL: startup room noise");
        end
        step(1048576);
        if(out_l!=917504||out_r!=917504)$fatal(1,"FAIL: room dry/headroom level");
        for(k=0;k<500;k=k+1)step(0);
        if(tail<10||different<10)$fatal(1,"FAIL: missing shared stereo tail");
        @(negedge clk);rst_n=0;repeat(4)@(negedge clk);rst_n=1;
        for(k=0;k<30;k=k+1)begin
            step(0);
            if(out_l!=0||out_r!=0)$fatal(1,"FAIL: old RAM tail audible after reset");
        end
        $display("PASS: shared room startup/reset quiet; bounded dry level; stereo tail without unknown RAM");$finish;
    end
    initial begin #100000;$fatal(1,"FAIL: piano room timeout");end
endmodule
