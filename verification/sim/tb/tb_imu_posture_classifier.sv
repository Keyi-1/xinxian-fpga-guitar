`timescale 1ns/1ps
module tb_imu_posture_classifier;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_ms=0,calibrate=0,ready=1,valid=0;
    reg signed [16:0] ax=100,ay=-200,az=8292,gx=10,gy=-20,gz=30;
    reg [15:0] sample_id=0;
    integer divider=0;
    always @(negedge clk)begin tick_ms=divider==999;divider=tick_ms ? 0 : divider+1;end
    wire calibrated,calibrating,healthy,event_valid,tone_valid,busy,deadline;
    wire [1:0] pose,tone;
    integer events=0,max_busy=0,busy_clocks=0;
    reg multiplier_done=0;
    imu_posture_classifier #(.CALIBRATION_LOG2(3),.HEALTH_MS(30),.STABLE_MS(40),.COOLDOWN_MS(80)) dut(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.calibrate(calibrate),.reader_ready(ready),
        .sample_valid(valid),.sample_sequence(sample_id),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .calibrated(calibrated),.calibrating(calibrating),.healthy(healthy),.stable_pose(pose),
        .pose_event(event_valid),.pose_timbre_valid(tone_valid),.pose_timbre(tone),.busy(busy),.deadline_miss(deadline));
    always @(posedge clk)begin
        if(event_valid)events=events+1;
        if(busy)begin busy_clocks=busy_clocks+1;if(busy_clocks>max_busy)max_busy=busy_clocks;end
        else busy_clocks=0;
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s pose%0d events%0d",why,pose,events);endtask
    task packet(input bit fresh=1);
        @(negedge clk);if(fresh)sample_id=sample_id+1'b1;valid=1;
        @(negedge clk);valid=0;repeat(9998)@(negedge clk);
    endtask
    task body(input integer x,y,z,rx=0,ry=0,rz=0);
        ax=x+100;ay=y-200;az=z+100;gx=rx+10;gy=ry-20;gz=rz+30;
    endtask
    integer before_events;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        repeat(12)packet();check(!calibrated && !healthy && events==0,"no implicit uncalibrated AUTO");
        @(negedge clk);calibrate=1;@(negedge clk);calibrate=0;
        repeat(3)packet();gz=10000;packet();check(dut.calibration_count==0,"moving calibration restarts");
        gz=30;repeat(8)packet();check(calibrated && !calibrating,"all calibration samples required");
        check(dut.bias_ax==100 && dut.bias_ay==-200 && dut.bias_az==100,"gravity preserved in Z offset");
        repeat(20)packet();check(healthy && pose==1 && tone_valid && tone==0 && events==1,"stable face-up");
        repeat(15)packet();check(events==1,"same pose never repeats default");
        body(0,3800,7258);repeat(40)packet();check(pose==1 && events==1,"face-up hold hysteresis below entry threshold");
        body(0,7100,4100);repeat(65)packet();check(pose==2 && tone_valid && tone==1 && events==2,"guitar pose after filter/stability");
        body(8192,0,0);repeat(65)packet();check(pose==3 && !tone_valid && events==3,"upright reports unavailable pipa without fake timbre");
        body(0,0,-8192);repeat(65)packet();check(pose==3 && events==3,"face-down excluded, retain selected pose");
        body(0,0,8192,4000);repeat(65)packet();check(events==3,"gyro rejects motion even near target gravity");
        body(0,0,8192);repeat(25)packet();check(pose==1 && events==4,"stationary transition after motion");
        repeat(20)packet(0);check(!healthy && events==4,"duplicate packet sequence cannot extend health");
        packet();check(!healthy,"first recovered packet cannot select");repeat(15)packet();
        check(healthy && events==4,"same pose after recovery cannot override manual selection");
        before_events=events;az=-32768;repeat(20)packet();check(events==before_events,"saturation and sign boundary rejected");
        body(0,0,8192);ready=0;repeat(10)packet();check(!healthy,"offline gates AUTO");ready=1;
        body(0,7100,4100);packet();check(!healthy && events==before_events,"recovery pose never immediate");
        repeat(70)packet();check(pose==2 && events==before_events+1,"new pose after complete recovery");
        check(!deadline && max_busy<1000,"bounded serial math under1000 clocks");
        wait(multiplier_done);
        $display("PASS: calibration/gravity/3 poses/hysteresis/motion/inversion/saturation/sequence/gap/recovery/no repeated events; max%0d clocks; serial1024 full-width products",max_busy);$finish;
    end
    reg mul_start=0;reg [35:0] ma=0,mb=0;wire mbusy,mdone;wire [71:0] result;
    reg [71:0] expected;
    integer index,latency;reg [31:0] random_state=32'h12345678;
    imu_serial_multiplier mul(.clk(clk),.rst_n(rst_n),.start(mul_start),.a(ma),.b(mb),.busy(mbusy),.done(mdone),.product(result));
    initial begin
        wait(rst_n);
        for(index=0;index<1024;index=index+1)begin
            @(negedge clk);
            random_state=(random_state<<13)^random_state;
            random_state=(random_state>>17)^random_state;
            random_state=(random_state<<5)^random_state;
            ma=index==0 ? 36'hfffffffff : {random_state,4'hf};
            mb=index==1 ? 0 : index==0 ? 36'hfffffffff : {4'h7,random_state};
            expected={36'd0,ma}*{36'd0,mb};mul_start=1;
            @(negedge clk);mul_start=0;latency=0;
            while(!mdone)begin @(negedge clk);latency=latency+1;end
            if(result!==expected || latency!=36)$fatal(1,"FAIL: serial multiply carry/latency index%0d",index);
        end
        multiplier_done=1;
    end
    initial begin #100000000;$fatal(1,"FAIL: classifier watchdog");end
endmodule
