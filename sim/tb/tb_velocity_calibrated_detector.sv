`timescale 1ns/1ps
module tb_velocity_calibrated_detector;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,sample_valid=0;reg [1:0] sample_string=0;reg [11:0] sample_data=2053;
    wire [3:0] pluck_valid,pending,fixed_pluck,fixed_pending;
    wire [7:0] velocity,fixed_velocity;wire [47:0] raw_adc,peak_adc;
    wire [31:0] stamp;integer trials=0,ch,value,j,k,expected,peak,events=0;
    four_string_pluck_detector dut(.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
        .sample_string(sample_string),.sample_data(sample_data),.pluck_valid(pluck_valid),
        .velocity_level(velocity),.raw_adc(raw_adc),.peak_adc(peak_adc),.event_timestamp(stamp),.capture_pending(pending));
    four_string_pluck_detector #(.FIXED_VELOCITY_ENABLE(1)) fixed_mode(.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
        .sample_string(sample_string),.sample_data(sample_data),.pluck_valid(fixed_pluck),
        .velocity_level(fixed_velocity),.raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(fixed_pending));
    function integer trigger(input integer c);
        case(c)0:trigger=220;1:trigger=100;2:trigger=80;default:trigger=100;endcase
    endfunction
    function integer grade(input integer c,m);
        case(c)
          0:grade=m>=620 ? 3 : m>=430 ? 2 : m>=280 ? 1 : 0;
          1:grade=m>=600 ? 3 : m>=400 ? 2 : m>=250 ? 1 : 0;
          2:grade=m>=400 ? 3 : m>=280 ? 2 : m>=150 ? 1 : 0;
          3:grade=m>=600 ? 3 : m>=380 ? 2 : m>=220 ? 1 : 0;
        endcase
    endfunction
    task reset;
        @(negedge clk);sample_valid=0;rst_n=0;repeat(2)@(negedge clk);rst_n=1;
    endtask
    task feed(input integer c,data,mask,g);
        @(negedge clk);sample_valid=1;sample_string=c;sample_data=data;
        @(posedge clk);#1;
        if(pluck_valid!==mask[3:0] || fixed_pluck!==pluck_valid || fixed_pending!==pending)
            $fatal(1,"FAIL: capture/event c%0d raw%0d expected%h got%h",c,data,mask,pluck_valid);
        if(mask)begin
            if(velocity[c*2+:2]!==g[1:0] || fixed_velocity[c*2+:2]!==2)
                $fatal(1,"FAIL: calibrated grade c%0d raw%0d expected%0d got%0d",c,data,g,velocity[c*2+:2]);
            events=events+1;
        end
        if(raw_adc[c*12+:12]!==data[11:0])$fatal(1,"FAIL: raw channel ordering");
        @(negedge clk);sample_valid=0;@(posedge clk);#1;
        if(pluck_valid!==0)$fatal(1,"FAIL: event wider than one clock");
    endtask
    initial begin
        // Every possible12-bit input on each channel, both polarities about2053;
        // below trigger is silent, threshold comparisons are inclusive.
        for(ch=0;ch<4;ch=ch+1)for(value=0;value<4096;value=value+1)begin
            reset();peak=value>=2053 ? value-2053 : 2053-value;expected=grade(ch,peak);
            feed(ch,value,0,0);
            for(j=1;j<=32;j=j+1)feed(ch,value,j==32 && peak>=trigger(ch) ? 1<<ch : 0,expected);
            if(pending!==0)$fatal(1,"FAIL: capture did not commit");
            trials=trials+1;
        end
        // Peak may occur at the first, last or any intermediate observation.
        for(ch=0;ch<4;ch=ch+1)for(k=0;k<=32;k=k+1)begin
            reset();feed(ch,2053+(k==0 ? 800 : trigger(ch)),0,0);
            for(j=1;j<=32;j=j+1)feed(ch,j==k ? 2853 : 2053,j==32 ? 1<<ch : 0,3);
        end
        // Ringing cannot retrigger after dead time without80 consecutive low samples.
        reset();feed(0,2673,0,0);repeat(31)feed(0,2673,0,0);feed(0,2673,1,3);
        repeat(450)feed(0,2673,0,0);repeat(79)feed(0,2073,0,0);feed(0,2074,0,0);
        repeat(79)feed(0,2073,0,0);
        if(dut.armed[0])$fatal(1,"FAIL: early rearm after noisy settle");
        feed(0,2073,0,0);if(!dut.armed[0])$fatal(1,"FAIL: exact inclusive20/80 rearm");
        feed(0,2333,0,0);repeat(31)feed(0,2053,0,0);feed(0,2053,1,1);
        // Four independent windows may overlap while samples are interleaved.
        reset();for(ch=0;ch<4;ch=ch+1)feed(ch,2853,0,0);
        for(j=1;j<=32;j=j+1)for(ch=0;ch<4;ch=ch+1)feed(ch,2053,j==32 ? 1<<ch : 0,3);
        reset();feed(1,2853,0,0);reset();repeat(40)feed(1,2053,0,0);
        $display("PASS: calibrated detector %0d exhaustive channel/raw trials,132 peak positions,full32-observation commit,fixed2 option,polarity,independent windows,ringing/rearm/reset; %0d events",trials,events);$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: calibration detector watchdog");end
endmodule
