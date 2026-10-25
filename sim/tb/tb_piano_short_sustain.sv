`timescale 1ns/1ps
module tb_piano_short_sustain;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,on=0,sustain=1;
    wire active,old_active,busy,old_busy,miss,old_miss;
    GSR GSR(.GSRI(1'b1));
`define PORTS .clk(clk),.rst_n(rst_n),.sample_ce(tick),.note_on(on),.note_off(1'b0), \
    .force_release(1'b0),.velocity_level(2'd3),.phase_inc(32'd23409859), \
    .timbre_blend(9'd0),.rock_blend(9'd0),.sustain_enable(sustain),.harmony_enable(1'b0), \
    .sample_valid(),.pcm_out(),.profile()
    // Lifetime is independent of modal count. One mode allows the full
    // production age range and sustain rollover to run economically.
    piano_voice_core #(.MODES(1),.HAMMER_ENABLE(0),.CONTROL_ENABLE(1)) dut(
        `PORTS,.active(active),.busy(busy),.deadline_miss(miss));
    short_before_piano_voice_core #(.MODES(1),.HAMMER_ENABLE(0),.CONTROL_ENABLE(1)) frozen(
        `PORTS,.active(old_active),.busy(old_busy),.deadline_miss(old_miss));
`undef PORTS
    integer n,new_end=0,old_end=0;
    task step;
        begin
            @(negedge clk);tick=1;
            @(negedge clk);tick=0;on=0;
            repeat(30)@(negedge clk);
            if(busy || old_busy || miss || old_miss)$fatal(1,"FAIL: lifetime deadline");
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;on=1;step();
        for(n=1;n<=518150;n=n+1)begin
            step();
            if(!active && new_end==0)new_end=n;
            if(!old_active && old_end==0)old_end=n;
        end
        if(new_end!=255997 || old_end!=518141)
            $fatal(1,"FAIL: sustained production lifetime new%0d old%0d",new_end,old_end);
        $display("PASS: production MAX131072 sustained lifetime new%0d/old%0d samples (~49.4%%); no age wrap, rollover or deadline",new_end,old_end);
        $finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: sustain watchdog");end
endmodule
