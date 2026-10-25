`timescale 1ns/1ps
module tb_performance_vibrato_gesture;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,enable=1,stable_valid=0;
    reg [15:0] frets=0;
    reg [3:0] pluck=0,active=15;
    wire [3:0] vibrato,note_on,note_off;
    wire [127:0] target;
    integer attacks=0,checks=0;
    performance_vibrato_gesture #(.MIN_RELEASE_SAMPLES(2),.MAX_RELEASE_SAMPLES(6),
        .WINDOW_SAMPLES(32)) dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable),
        .stable_valid(stable_valid),.stable_fret_id(frets),.pluck_valid(pluck),
        .note_on(note_on),.voice_active(active),.vibrato_enable(vibrato));
    guitar_play_control policy(.clk(clk),.rst_n(rst_n),.sample_tick(tick),
        .stable_valid(stable_valid),.stable_fret_id(frets),.pluck_valid(pluck),
        .voice_active(active),.smoothed_phase_inc(128'd0),.note_on(note_on),
        .note_off(note_off),.target_phase_inc(target));
    always @(posedge clk)if(rst_n)begin
        if(note_on!=0)attacks=attacks+1;
        if(note_off!=0)$fatal(1,"FAIL: gesture introduced note_off");
    end
    task set_frets(input [15:0] value);
        @(negedge clk);frets=value;stable_valid=1;
        @(negedge clk);stable_valid=0;#1;
    endtask
    task samples(input integer count);
        repeat(count)begin
            @(negedge clk);tick=1;
            @(negedge clk);tick=0;#1;
        end
    endtask
    task tap_string(input integer s,input integer length);
        reg [15:0] pressed;
        reg [127:0] held_pitch;
        pressed=frets;
        held_pitch=target;
        set_frets(frets & ~(16'hf<<(s*4)));
        if(target!==held_pitch)
            $fatal(1,"FAIL: release did not retain the fretted pitch");
        if(vibrato[s])$fatal(1,"FAIL: release did not cancel vibrato");
        samples(length);set_frets(pressed);checks=checks+1;
    endtask
    task restart;
        @(negedge clk);enable=0;
        @(negedge clk);enable=1;
        set_frets(16'h3333);
    endtask
    integer i;
    initial begin
        repeat(3)@(negedge clk);rst_n=1;set_frets(16'h3333);
        @(negedge clk);pluck=1;
        @(negedge clk);pluck=0;
        samples(1);
        samples(1);
        if(attacks!=1)$fatal(1,"FAIL: initial real pluck");
        tap_string(0,2);if(vibrato)$fatal(1,"FAIL: one tap enabled vibrato");
        tap_string(0,6);if(vibrato)$fatal(1,"FAIL: two taps enabled vibrato");
        tap_string(0,2);if(vibrato!==1)$fatal(1,"FAIL: three taps did not enable string0");
        if(attacks!=1)$fatal(1,"FAIL: fret taps restarted Attack");
        set_frets(16'h3334);if(vibrato)$fatal(1,"FAIL: changed fret retained vibrato");
        restart;
        for(i=0;i<4;i=i+1)begin
            tap_string(i,2);tap_string(i,2);tap_string(i,2);
            if(!vibrato[i])$fatal(1,"FAIL: independent string gesture %d",i);
        end
        if(vibrato!==15)$fatal(1,"FAIL: four string independence");
        @(negedge clk);pluck=2;@(negedge clk);pluck=0;#1;
        if(vibrato!==13)$fatal(1,"FAIL: real restrike did not cancel only its string");
        active=11;@(negedge clk);#1;
        if(vibrato!==9)$fatal(1,"FAIL: naturally ended voice kept vibrato");
        active=15;restart;
        tap_string(0,1);tap_string(0,2);tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: too-short release counted");
        tap_string(0,2);if(vibrato!==1)$fatal(1,"FAIL: minimum boundary");
        restart;
        tap_string(0,7);tap_string(0,2);tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: too-long release counted");
        restart;
        tap_string(0,2);samples(33);tap_string(0,2);tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: expired window counted");
        restart;
        tap_string(0,2);set_frets(16'h3334);tap_string(0,2);tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: different frets shared a gesture");
        @(negedge clk);enable=0;
        repeat(3)tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: game/menu enabled vibrato");
        @(negedge clk);enable=1;
        tap_string(0,2);tap_string(0,2);
        if(vibrato)$fatal(1,"FAIL: mode reentry reused taps");
        @(negedge clk);rst_n=0;repeat(2)@(negedge clk);rst_n=1;
        if(vibrato)$fatal(1,"FAIL: reset retained gesture");
        $display("PASS: performance vibrato gesture %0d taps, four strings, timing boundaries, no Attack/off, held-pitch release, mode/reset/natural-end/restrike",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"FAIL: gesture timeout");end
endmodule
