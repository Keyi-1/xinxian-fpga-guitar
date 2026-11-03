`timescale 1ns/1ps
module tb_guitar_visual_telemetry;
    reg clk=0,rst_n=0,tick=0,valid=0;
    always #5 clk=~clk;
    reg [127:0] increments={32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F};
    reg [3:0] notes=0,active=15;
    reg [95:0] pcm={24'h800000,24'd2000000,24'd600000,24'd300000};
    wire [399:0] snapshot;
    guitar_visual_telemetry dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),.voice_sample_valid(valid),
        .phase_inc(increments),.note_on(notes),.voice_active(active),.fret_id(16'h4321),.voice_pcm(pcm),.snapshot(snapshot));
    integer i;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;repeat(3) @(negedge clk);
        if(snapshot[288+:11]!=330 || snapshot[299+:11]!=247 || snapshot[310+:11]!=196 || snapshot[321+:11]!=147)
            $fatal(1,"FAIL: DDS-to-Hz rounding");
        tick=1;notes=9;@(negedge clk);tick=0;notes=0;
        if(snapshot[368+:8]!=1 || snapshot[392+:8]!=1 || snapshot[376+:8]!=0)
            $fatal(1,"FAIL: accepted pluck counters");
        tick=1;@(negedge clk);tick=0;
        if(snapshot[31:0]!=increments[31:0] || snapshot[127:96]!=increments[127:96])
            $fatal(1,"FAIL: visual phase does not track sample DDS");
        valid=1;repeat(256) @(negedge clk);valid=0;
        if(snapshot[352+:4]!=2 || snapshot[356+:4]!=4 || snapshot[360+:4]!=15 || snapshot[364+:4]!=15)
            $fatal(1,"FAIL: signed PCM peak/saturation levels");
        active=0;valid=1;repeat(256) @(negedge clk);valid=0;
        if(snapshot[367:352]!=0) $fatal(1,"FAIL: inactive amplitude labels");
        $display("PASS: audible DDS/Hz, sample phase, pluck counters and signed per-voice PCM peaks");$finish;
    end
endmodule
