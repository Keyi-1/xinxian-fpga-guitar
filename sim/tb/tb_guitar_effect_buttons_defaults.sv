`timescale 1ns/1ps
// Test the unmodified, full-width 20 ms / 1 s hardware counters. No force.
module tb_guitar_effect_buttons_defaults;
    reg clk=0;always #40.690104 clk=~clk;
    reg rst_n=0,k1=1,k2=1,k3=1;
    wire timbre,chorus,sustain,reverb,harmony;
    wire rock;
    wire [1:0] tone;
    guitar_effect_buttons dut(
        .load_timbre(1'b0),.loaded_timbre(2'd0),.rock_select(rock),.timbre_mode(tone),
        .clk(clk),.rst_n(rst_n),.key_timbre_n(k1),.key_chorus_n(k2),.key_space_n(k3),
        .timbre_select(timbre),.chorus_enable(chorus),.sustain_enable(sustain),
        .reverb_enable(reverb),.space_mode(),.harmony_enable(harmony));
    task clocks(input integer n);repeat(n)@(negedge clk);endtask
    initial begin
        clocks(8);rst_n=1;clocks(8);
        k1=0;clocks(240000);
        if(timbre)$fatal(1,"FAIL: hardware debounce too short");
        clocks(10000);if(!timbre)$fatal(1,"FAIL: hardware key 1 threshold");
        k1=1;k3=0;clocks(250000);
        if(!sustain||reverb)$fatal(1,"FAIL: hardware key 3");
        k3=1;k2=0;clocks(250000);
        clocks(11000000);
        if(harmony||chorus)$fatal(1,"FAIL: hardware long threshold too short");
        clocks(1400000);
        if(!harmony||chorus)$fatal(1,"FAIL: hardware long key 2");
        clocks(1000000);if(!harmony)$fatal(1,"FAIL: held long key repeats");
        k2=1;clocks(250000);if(chorus)$fatal(1,"FAIL: long release switched chorus");
        k2=0;clocks(250000);k2=1;clocks(250000);
        if(!chorus||!harmony)$fatal(1,"FAIL: hardware short key 2");
        k1=0;clocks(250000);if(!rock||timbre||tone!=2)$fatal(1,"FAIL: hardware rock cycle");
        k1=1;clocks(250000);k1=0;clocks(250000);k1=1;clocks(250000);
        if(rock||timbre||tone!=0)$fatal(1,"FAIL: hardware piano wrap");
        $display("PASS: actual 245760-cycle debounce and 12288000-cycle long hold; default hardware key mappings; no forced state");
        $finish;
    end
endmodule
