`timescale 1ns/1ps
module tb_game_miss_audio_cue;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,enabled=0,trigger=0;
    reg [1:0] divider=0;
    wire valid=divider==3;
    always @(posedge clk)divider<=divider+1'b1;
    reg signed [23:0] left=24'sd12345,right=-24'sd54321;
    wire signed [23:0] out_left,out_right;
    game_miss_audio_cue dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),.enabled(enabled),.trigger(trigger),
        .left_in(left),.right_in(right),.left_out(out_left),.right_out(out_right));
    integer n,changed=0,full_samples=0;
    reg signed [24:0] expected_l,expected_r;
    function automatic signed [23:0] saturate(input signed [24:0] value);
        if(value>25'sd8388607)saturate=24'sh7fffff;
        else if(value < -25'sd8388608)saturate=24'sh800000;
        else saturate=value[23:0];
    endfunction
    task fire;
        @(negedge clk);trigger=1;@(negedge clk);trigger=0;
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        // Disabled bypass must preserve every bit, despite trigger noise.
        for(n=0;n<300;n=n+1)begin
            @(negedge clk);left=$random;right=$random;trigger=n[0];#1;
            if(out_left!==left || out_right!==right)$fatal(1,"FAIL: disabled cue changed musical PCM");
        end
        trigger=0;left=0;right=0;enabled=1;fire();wait(dut.remaining!=0);
        while(dut.remaining!=0)begin
            @(negedge clk);
            if(valid)begin
                full_samples=full_samples+1;
                if(out_left!=0)changed=changed+1;
                if(out_left!==out_right || out_left>24'sd253952 || out_left < -24'sd253952)
                    $fatal(1,"FAIL: cue channel/amplitude mismatch");
            end
        end
        if(full_samples!=1440 || changed<1000)$fatal(1,"FAIL: cue length/audibility %0d/%0d",full_samples,changed);
        left=24'sh7ffff0;right=24'sh800010;fire();wait(dut.remaining!=0);
        for(n=0;n<160;n=n+1)begin
            @(negedge clk);
            expected_l=$signed({left[23],left})+$signed({dut.cue[23],dut.cue});
            expected_r=$signed({right[23],right})+$signed({dut.cue[23],dut.cue});
            if(out_left!==saturate(expected_l) || out_right!==saturate(expected_r))
                $fatal(1,"FAIL: cue mix wrapped instead of saturating");
        end
        enabled=0;#1;
        if(out_left!==left || out_right!==right)$fatal(1,"FAIL: mode exit did not restore direct musical PCM");
        @(negedge clk);enabled=1;rst_n=0;@(negedge clk);rst_n=1;
        repeat(8)@(negedge clk);
        if(dut.remaining!=0 || dut.pending)$fatal(1,"FAIL: reset retained cue");
        $display("PASS: Miss cue 1440 samples, stereo identity, bounded level, saturated mix and exact bypass/reset");$finish;
    end
    initial begin #2000000;$fatal(1,"FAIL: Miss cue watchdog");end
endmodule
