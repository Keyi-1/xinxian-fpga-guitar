`timescale 1ns/1ps
module tb_imu_calibration_full;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,calibrate=0,ready=1,valid=0;
    reg signed [16:0] ax=100,ay=-200,az=8292;
    reg [15:0] sample_id=0;integer d=0;
    always @(negedge clk)begin tick=d==49;d=tick ? 0 : d+1;end
    wire calibrated,calibrating,healthy,deadline;
    imu_posture_classifier dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),.calibrate(calibrate),
        .reader_ready(ready),.sample_valid(valid),.sample_sequence(sample_id),
        .ax(ax),.ay(ay),.az(az),.gx(17'sd10),.gy(-17'sd20),.gz(17'sd30),
        .calibrated(calibrated),.calibrating(calibrating),.healthy(healthy),.stable_pose(),
        .pose_event(),.pose_timbre_valid(),.pose_timbre(),.busy(),.deadline_miss(deadline));
    task packet;
        @(negedge clk);sample_id=sample_id+1'b1;valid=1;@(negedge clk);valid=0;repeat(498)@(negedge clk);
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;calibrate=1;@(negedge clk);calibrate=0;
        repeat(100)packet();
        ax=1800;packet();if(dut.calibration_count!=0)$fatal(1,"FAIL: acceleration jump must restart calibration");
        ax=100;repeat(100)packet();ready=0;repeat(5)@(negedge clk);ready=1;
        if(dut.calibration_count!=0)$fatal(1,"FAIL: bus fault must restart calibration");
        repeat(255)packet();if(calibrated || !calibrating)$fatal(1,"FAIL: premature256-sample calibration");
        packet();if(!calibrated || calibrating || healthy)$fatal(1,"FAIL: exact256 and health warmup");
        if(dut.bias_ax!=100 || dut.bias_ay!=-200 || dut.bias_az!=100 ||
            dut.bias_gx!=10 || dut.bias_gy!=-20 || dut.bias_gz!=30 || deadline)$fatal(1,"FAIL: full-width signed sums/offsets");
        $display("PASS: production256 calibration count/signed means/preserve8192 gravity/motion and bus-fault restart");$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: calibration watchdog");end
endmodule
