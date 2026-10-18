`timescale 1ns/1ps
module tb_guitar_effect_buttons;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,k1=1,k2=1,k3=1;
    wire timbre,chorus,sustain,reverb,harmony;
    wire rock;
    wire [1:0] tone;
    wire [1:0] space;
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(30)) dut(.manual_timbre_press(),
        .load_timbre(1'b0),.loaded_timbre(2'd0),.rock_select(rock),.timbre_mode(tone),
        .clk(clk),.rst_n(rst_n),.key_timbre_n(k1),.key_chorus_n(k2),.key_space_n(k3),
        .timbre_select(timbre),.chorus_enable(chorus),.sustain_enable(sustain),
        .reverb_enable(reverb),.space_mode(space),.harmony_enable(harmony));
    task clocks(input integer n);repeat(n)@(negedge clk);endtask
    task tap(input integer key);
        if(key==1)k1=0;else if(key==2)k2=0;else k3=0;
        clocks(10);k1=1;k2=1;k3=1;clocks(10);
    endtask
    initial begin
        clocks(5);rst_n=1;clocks(5);
        k1=0;clocks(1);k1=1;clocks(6);
        if(timbre)$fatal(1,"FAIL: contact bounce switched timbre");
        tap(1);if(!timbre)$fatal(1,"FAIL: first timbre");
        k1=0;clocks(80);if(timbre||!rock||tone!=2)$fatal(1,"FAIL: held rock timbre repeats");
        k1=1;clocks(10);
        tap(1);if(timbre||rock||tone!=0)$fatal(1,"FAIL: three timbre wrap");
        tap(2);if(!chorus||harmony)$fatal(1,"FAIL: short key 2");
        k2=0;clocks(80);if(!harmony||!chorus)$fatal(1,"FAIL: long key 2");
        k2=1;clocks(10);if(!chorus)$fatal(1,"FAIL: long release toggled chorus");
        k2=0;clocks(80);k2=1;clocks(10);
        if(harmony||!chorus)$fatal(1,"FAIL: second long hold / rearm");
        tap(2);if(chorus)$fatal(1,"FAIL: chorus off");
        tap(3);if(space!=1||!sustain||reverb)$fatal(1,"FAIL: sustain state");
        k3=0;clocks(80);
        if(space!=2||sustain||!reverb||harmony)$fatal(1,"FAIL: room or held key 3");
        k3=1;clocks(10);tap(3);
        if(space!=0||sustain||reverb)$fatal(1,"FAIL: dry wrap");
        $display("PASS: key 1 piano/bright/rock wrap; key 2 short chorus / long harmony without double action; key 3 dry/sustain/light room; bounce and held-key rejection");
        $finish;
    end
endmodule
