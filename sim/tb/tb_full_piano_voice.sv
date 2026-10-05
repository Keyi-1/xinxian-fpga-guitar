`timescale 1ns/1ps
module tb_full_piano_voice;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0,off=0,sustain=0,harmony=0;
    reg [1:0] velocity=0;
    reg [31:0] inc=0;
    reg [8:0] blend=0;
    wire valid,active,busy,miss;
    wire signed [23:0] pcm;
    piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(off),
        .velocity_level(velocity),.phase_inc(inc),.timbre_blend(blend),
        .sustain_enable(sustain),.harmony_enable(harmony),.sample_valid(valid),
        .pcm_out(pcm),.active(active),.busy(busy),.deadline_miss(miss),.profile());
    integer f,got,n,vel_i,on_i,off_i,blend_i,sustain_i,harmony_i,active_i,cycles;
    integer enabled_modes,nonzero_modes,max_nonzero=0;
    reg signed [23:0] expected;
    // Observe each oscillator's actual computed amplitude, not just ROM data.
    always @(posedge clk)if(rst_n && dut.state==5)begin
        if(dut.mode_enabled)enabled_modes=enabled_modes+1;
        if(dut.bright_amplitude!=0)nonzero_modes=nonzero_modes+1;
    end
    initial begin
        f=$fopen("full_piano_golden.txt","r");
        if(!f)$fatal(1,"FAIL: full piano reference missing");
        repeat(5)@(negedge clk);rst_n=1;
        for(n=0;n<12000;n=n+1)begin
            got=$fscanf(f,"%h %d %d %d %d %d %d %h %d\n",inc,vel_i,on_i,off_i,blend_i,sustain_i,harmony_i,expected,active_i);
            if(got!=9)$fatal(1,"FAIL: full piano reference row %0d",n);
            @(negedge clk);ce=1;on=on_i;off=off_i;velocity=vel_i;
            blend=blend_i;sustain=sustain_i;harmony=harmony_i;
            enabled_modes=0;nonzero_modes=0;
            @(negedge clk);ce=0;on=0;off=0;cycles=1;
            while(!valid)begin @(negedge clk);cycles=cycles+1;end
            if(cycles>=256||miss||busy||pcm!==expected||active!==active_i[0])
                $fatal(1,"FAIL: full sample %0d actual=%h expected=%h cycles=%0d",n,pcm,expected,cycles);
            if(nonzero_modes>max_nonzero)max_nonzero=nonzero_modes;
            if(enabled_modes>32)$fatal(1,"FAIL: exceeded 32 modes");
            repeat(256-cycles)@(negedge clk);
        end
        if(max_nonzero!=32)$fatal(1,"FAIL: only %0d nonzero alternate components",max_nonzero);
        $display("PASS: 12000 bit-exact FULL samples; all 32 modes produce nonzero amplitudes; fifth pitch, timbre crossfade, sustain/release and re-strike within 256 clocks");
        $finish;
    end
    initial begin #40000000;$fatal(1,"FAIL: full piano timeout");end
endmodule
