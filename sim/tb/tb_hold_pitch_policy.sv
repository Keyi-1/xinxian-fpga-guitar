`timescale 1ns/1ps
module tb_hold_pitch_policy;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,stable=0;
    reg [15:0] fret=0;
    reg [3:0] pluck=0;
    wire [3:0] on,off;
    wire [127:0] target;
    localparam [127:0] OPEN={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
    reg [127:0] expected;
    guitar_play_control dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),
        .stable_valid(stable),.stable_fret_id(fret),.pluck_valid(pluck),
        .voice_active(4'hf),.smoothed_phase_inc(128'd0),.note_on(on),.note_off(off),.target_phase_inc(target));
    task select(input [15:0] value);
        @(negedge clk);fret=value;stable=1;
        @(negedge clk);stable=0;#1;
    endtask
    integer s,f,checks=0;
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        if(target!==OPEN)$fatal(1,"FAIL: reset open defaults");
        for(f=1;f<=8;f=f+1)begin
            select({4{4'(f)}});expected=target;
            select(0);
            repeat(7)@(negedge clk);
            if(target!==expected || on || off)$fatal(1,"FAIL: release changed pitch or envelope events");
            for(s=0;s<4;s=s+1)begin
                // Queue a real open-string pluck between sample ticks. It
                // immediately selects open pitch and launches once on tick.
                @(negedge clk);pluck=4'(1<<s);#1;
                expected[s*32+:32]=OPEN[s*32+:32];
                if(target!==expected || on || off)$fatal(1,"FAIL: queued open pluck/independence");
                @(negedge clk);pluck=0;
                @(negedge clk);tick=1;#1;
                if(on!==4'(1<<s))$fatal(1,"FAIL: queued pluck lost");
                @(negedge clk);tick=0;#1;
                if(target!==expected || on || off)$fatal(1,"FAIL: open pitch not retained after pluck");
                checks=checks+1;
            end
        end
        select(16'h8765);expected=target;
        // A pluck arriving exactly on a sample boundary keeps direct Attack.
        @(negedge clk);tick=1;pluck=15;#1;
        if(on!==15 || target!==expected)$fatal(1,"FAIL: same-tick pluck");
        @(negedge clk);tick=0;pluck=0;select(0);
        if(target!==expected || on || off)$fatal(1,"FAIL: final release");
        $display("PASS: held-pitch release for all8 frets/four strings, %0d queued real-open plucks, same-tick Attack, no note_off/retrigger, independent string targets",checks);
        $finish;
    end
endmodule
