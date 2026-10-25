`timescale 1ns/1ps
module tb_vibrato_gesture_countdown;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,enable=1,stable_valid=0;
    reg [15:0] frets=16'h3333;reg [3:0] pluck=0,note_on=0,active=15;
    wire [3:0] current[0:1],previous[0:1];
    integer cycles=0,samples=0,n,i;
    reg [31:0] random_state=32'h50a5729b;
    function [31:0] next_random(input [31:0] q);
        reg [31:0] z;begin z=q^(q<<13);z=z^(z>>17);next_random=z^(z<<5);end
    endfunction
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:pair
        localparam MINIMUM=g==0 ? 2 : 2880;
        localparam MAXIMUM=g==0 ? 6 : 9600;
        localparam WINDOW=g==0 ? 32 : 28800;
`define ARGS .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable),.stable_valid(stable_valid), \
    .stable_fret_id(frets),.pluck_valid(pluck),.note_on(note_on),.voice_active(active)
        performance_vibrato_gesture #(.MIN_RELEASE_SAMPLES(MINIMUM),.MAX_RELEASE_SAMPLES(MAXIMUM),.WINDOW_SAMPLES(WINDOW)) dut(`ARGS,.vibrato_enable(current[g]));
        vibrato_v2_performance_vibrato_gesture #(.MIN_RELEASE_SAMPLES(MINIMUM),.MAX_RELEASE_SAMPLES(MAXIMUM),.WINDOW_SAMPLES(WINDOW)) frozen(`ARGS,.vibrato_enable(previous[g]));
`undef ARGS
        integer s;
        always @(posedge clk)begin
            #1;
            if({current[g],dut.previous_fret,dut.pending,dut.window_active} !==
               {previous[g],frozen.previous_fret,frozen.pending,frozen.window_active})
                $fatal(1,"FAIL: countdown gesture observable/state mismatch pair%0d cycle%0d",g,cycles);
            if(rst_n)for(s=0;s<4;s=s+1)begin
                if(dut.taps[s]!==frozen.taps[s])$fatal(1,"FAIL: taps differ");
                if(dut.pending[s] && dut.release_samples[s]+frozen.release_samples[s]!=MAXIMUM+1)
                    $fatal(1,"FAIL: exact remaining+elapsed release invariant");
                if(dut.window_active[s] && dut.window_samples[s]+frozen.window_samples[s]!=WINDOW)
                    $fatal(1,"FAIL: exact remaining+elapsed window invariant");
            end
        end
    end endgenerate
    task periods(input integer count);
        repeat(count)begin
            @(negedge clk);tick=1;@(negedge clk);tick=0;
            repeat(6)@(negedge clk);samples=samples+1;
        end
    endtask
    task fret(input [15:0] value);
        @(negedge clk);frets=value;stable_valid=1;
        @(negedge clk);stable_valid=0;
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;fret(16'h3333);
        fret(0);periods(2880);fret(16'h3333);periods(40);
        fret(0);periods(6000);fret(16'h3333);periods(40);
        fret(0);periods(9600);fret(16'h3333);periods(40);
        if(current[1]!==15)$fatal(1,"FAIL: production min/max three taps");
        fret(0);periods(9601);fret(16'h3333);periods(30000);
        // Deliberately collide sample/fret/pluck/note/enable/reset edges.
        for(n=0;n<400000;n=n+1)begin
            @(negedge clk);cycles=cycles+1;random_state=next_random(random_state);
            tick=n%8==0;stable_valid=random_state[6:0]==0;
            if(stable_valid)frets={4'(random_state[15:12]%9),4'(random_state[19:16]%9),4'(random_state[23:20]%9),4'(random_state[27:24]%9)};
            pluck=random_state[12:0]==0 ? random_state[19:16] : 0;
            note_on=random_state[14:0]==1 ? random_state[23:20] : 0;
            if(random_state[14:0]==2)active=random_state[27:24];
            if(random_state[13:0]==3)enable=~enable;
            rst_n=random_state[16:0]!=4;
            if(tick)samples=samples+1;
        end
        repeat(4)@(negedge clk);
        $display("PASS: frozen V2 gesture versus countdown, production+scaled parameters, %0d samples/%0d random edge cycles, all4 strings, exact timer invariants/min/max/saturation/window/reset/mode/pluck/note collisions",samples,cycles);
        $finish;
    end
    initial begin #50000000;$fatal(1,"FAIL: countdown watchdog");end
endmodule
