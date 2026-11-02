`timescale 1ns/1ps
// Both models receive identical signed samples, including sensor offsets.
// The frozen model demonstrates the former negative-neck blind spot.
module tb_imu_bidirectional;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_ms=0,calibrate=0,valid=0;
    reg signed [16:0] ax=100,ay=-200,az=8292,gx=10,gy=-20,gz=30;
    reg [15:0] seq=0;
    integer divider=0,events=0;
    always @(negedge clk)begin tick_ms=divider==999;divider=tick_ms ? 0 : divider+1;end
    wire calibrated,healthy,deadline,old_calibrated,old_healthy,old_deadline;
    wire [1:0] pose,old_pose,tone;
    wire event_valid,tone_valid;
    `define INPUTS .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.calibrate(calibrate),.reader_ready(1'b1), \
        .sample_valid(valid),.sample_sequence(seq),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz)
    imu_posture_classifier dut(`INPUTS,.calibrated(calibrated),.calibrating(),.healthy(healthy),
        .stable_pose(pose),.pose_event(event_valid),.pose_timbre_valid(tone_valid),.pose_timbre(tone),.busy(),.deadline_miss(deadline));
    accepted_imu_posture_classifier old(`INPUTS,.calibrated(old_calibrated),.calibrating(),.healthy(old_healthy),
        .stable_pose(old_pose),.pose_event(),.pose_timbre_valid(),.pose_timbre(),.busy(),.deadline_miss(old_deadline));
    `undef INPUTS
    always @(posedge clk)if(event_valid)events=events+1;
    task check(input bit ok,input string why);
        if(!ok)$fatal(1,"FAIL: %s pose=%0d old=%0d events=%0d",why,pose,old_pose,events);
    endtask
    task packet;
        @(negedge clk);seq=seq+1'b1;valid=1;@(negedge clk);valid=0;repeat(9998)@(negedge clk);
    endtask
    task body(input integer x,y,z);
        ax=x+100;ay=y-200;az=z+100;
    endtask
    task flat;
        body(0,0,8192);repeat(220)packet();
        check(pose==1 && old_pose==1 && tone_valid && tone==0,"flat restores piano in both models");
    endtask
    task guitar(input integer x,y,z,input string why);
        body(x,y,z);repeat(220)packet();
        check(pose==2 && tone_valid && tone==1,why);
    endtask
    integer prior_events;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;calibrate=1;@(negedge clk);calibrate=0;
        repeat(255)packet();check(!calibrated,"production calibration requires all256 packets");
        packet();check(calibrated && old_calibrated,"production256 calibration complete");
        flat();check(healthy && old_healthy,"production health delay");
        guitar(-6000,0,5578,"negative X47deg selects guitar");
        check(old_pose==1,"reproduced frozen FLAT in accepted negative-X classifier");
        flat();guitar(6000,0,5578,"positive X47deg selects guitar");
        check(old_pose==2,"original positive-X behavior preserved");
        flat();guitar(0,-7100,4100,"negative Y60deg selects guitar");
        check(old_pose==2,"original negative-Y behavior preserved");
        flat();guitar(0,7100,4100,"positive Y60deg selects guitar");
        check(old_pose==2,"original positive-Y behavior preserved");
        flat();body(-8192,0,0);repeat(220)packet();
        check(pose==3 && !tone_valid,"reverse upright reported without selecting a fake timbre");
        flat();prior_events=events;gx=4010;body(-6000,0,5578);repeat(220)packet();
        check(pose==1 && events==prior_events,"gyro rejects ongoing motion");
        gx=10;repeat(220)packet();check(pose==2,"stationary negative tilt recovers");
        prior_events=events;repeat(220)packet();check(events==prior_events,"no repeated pose command");
        check(!deadline && !old_deadline,"arithmetic meets every sample deadline");
        $display("PASS: reproduced old negative-X FLAT; production256 calibration/health/stability, both signs of X/Y tilt, reverse upright, motion rejection and no repeated events; %0d packets",seq);$finish;
    end
    initial begin #600000000;$fatal(1,"FAIL: bidirectional watchdog");end
endmodule
