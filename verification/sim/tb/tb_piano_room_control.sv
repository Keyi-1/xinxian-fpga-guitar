`timescale 1ns/1ps
module tb_piano_room_control;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,enable=0;
    reg signed [23:0] x=0;
    wire valid,busy;
    wire signed [23:0] l,r;
    wire [8:0] blend;
    piano_stereo_room #(.CONTROL_ENABLE(1),.DELAY_A(7),.DELAY_B(11),.DELAY_C(17)) dut(
        .clk(clk),.rst_n(rst_n),.sample_valid_in(ce),.left_in(x),.right_in(x),.room_enable(enable),
        .sample_valid(valid),.left_out(l),.right_out(r),.effect_blend(blend),.effect_busy(busy));
    integer a[0:6],b[0:10],c[0:16];
    integer pa=0,pb=0,pc=0,n=0,bl=0,j,tails=0;
    longint signed ta,tb,tc,source,dry,wet_l,wet_r,expect_l,expect_r;
    function integer clip(input longint signed z);
        if(z>8388607)clip=8388607;else if(z < -8388608)clip=-8388608;else clip=z;
    endfunction
    task step(input integer value);
        ta=n>=7?a[pa]:0;tb=n>=11?b[pb]:0;tc=n>=17?c[pc]:0;
        source=(value>>>2)+(value>>>3);
        a[pa]=clip(source+(tb>>>1)+(tb>>>3));
        b[pb]=clip(source+(tc>>>1)+(tc>>>3));
        c[pc]=clip(source+(ta>>>1)+(ta>>>3));
        pa=(pa+1)%7;pb=(pb+1)%11;pc=(pc+1)%17;
        if(enable&&bl<256)bl=bl+1;else if(!enable&&bl>0)bl=bl-1;
        dry=value-(value>>>3);
        wet_l=value-(value>>>2)+(ta>>>3)+(tc>>>3);
        wet_r=value-(value>>>2)+(tb>>>3)+(tc>>>3);
        expect_l=clip((dry*(256-bl)+wet_l*bl)>>>8);
        expect_r=clip((dry*(256-bl)+wet_r*bl)>>>8);
        @(negedge clk);x=value;ce=1;@(negedge clk);ce=0;
        wait(valid);#1;
        if($isunknown({l,r})||l!==expect_l[23:0]||r!==expect_r[23:0]||blend!=bl)
            $fatal(1,"FAIL: room frame %0d actual=%d/%d expected=%d/%d",n,l,r,expect_l,expect_r);
        if(value==0&&(l!=0||r!=0))tails=tails+1;
        repeat(3)@(negedge clk);n=n+1;
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        step(1048576);repeat(50)step(0);
        enable=1;repeat(256)step(0);step(1048576);repeat(100)step(0);
        if(tails<20||blend!=256||busy)$fatal(1,"FAIL: audible room tail/crossfade");
        for(j=0;j<100;j=j+1)step(j%2 ? 8000000 : -8000000);
        enable=0;repeat(256)step(0);step(-1048576);repeat(30)step(0);
        if(blend!=0||busy)$fatal(1,"FAIL: room off");
        $display("PASS: normalized 5/8 feedback room; signed sample-domain oracle, full-scale headroom, stereo tail, crossfade and exact dry bypass");$finish;
    end
endmodule
