`timescale 1ns/1ps
module tb_third_string_sensitivity;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0;reg [1:0] channel=0;reg [11:0] data=2053;
    wire [3:0] events,old_events,pending,old_pending;
    wire [7:0] velocity,old_velocity;
    integer counts[0:3];integer old_count2=0,c,j,polarity,amplitude;
    four_string_pluck_detector dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),
      .sample_string(channel),.sample_data(data),.pluck_valid(events),.velocity_level(velocity),
      .raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(pending));
    four_string_pluck_detector #(.TRIGGER_THRESHOLD_CH2(80)) previous(.clk(clk),.rst_n(rst_n),.sample_valid(valid),
      .sample_string(channel),.sample_data(data),.pluck_valid(old_events),.velocity_level(old_velocity),
      .raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(old_pending));
    always @(posedge clk)begin
      #1;
      if(rst_n)begin
        if({events[3],events[1:0],pending[3],pending[1:0],velocity[7:6],velocity[3:0]}!==
           {old_events[3],old_events[1:0],old_pending[3],old_pending[1:0],old_velocity[7:6],old_velocity[3:0]})
          $fatal(1,"FAIL: CH2 sensitivity changed another string");
        for(integer n=0;n<4;n=n+1)if(events[n])counts[n]=counts[n]+1;
        if(old_events[2])old_count2=old_count2+1;
      end
    end
    task feed(input integer ch,raw);
      @(negedge clk);valid=1;channel=ch;data=raw;@(negedge clk);valid=0;
    endtask
    task reset;
      @(negedge clk);rst_n=0;valid=0;repeat(2)@(negedge clk);
      for(integer n=0;n<4;n=n+1)counts[n]=0;
      old_count2=0;rst_n=1;
    endtask
    initial begin
      for(polarity=-1;polarity<=1;polarity=polarity+2)
      for(amplitude=60;amplitude<80;amplitude=amplitude+1)begin
        reset();
        for(j=0;j<40;j=j+1)for(c=0;c<4;c=c+1)
          feed(c,c==2 ? 2053+polarity*amplitude : 2853);
        if(counts[2]!=1 || old_count2!=0 || velocity[5:4]!=0 || pending[2])
          $fatal(1,"FAIL: newly admitted CH2 light strike amplitude%0d",amplitude);
        for(c=0;c<4;c=c+1)if(c!=2 && counts[c]!=1)$fatal(1,"FAIL: another string lost");
      end
      // Exact boundary, both polarities, no first-sample-only early event.
      for(polarity=-1;polarity<=1;polarity=polarity+2)begin
        reset();repeat(40)feed(2,2053+polarity*59);
        if(counts[2]!=0 || pending[2])$fatal(1,"FAIL: below60 triggered");
        feed(2,2053+polarity*60);repeat(31)feed(2,2053);
        if(counts[2]!=0 || !pending[2])$fatal(1,"FAIL: CH2 early capture commit");
        feed(2,2053);if(counts[2]!=1 || velocity[5:4]!=0)$fatal(1,"FAIL: exact60 commit");
      end
      $display("PASS: CH2-only80->60,40 bipolar60..79 light-strike scenarios newly accepted; CH0/1/3 events/grades/pending cycle-equivalent; +/-59 silent,+/-60 inclusive after full32 subsequent samples");$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: CH2 sensitivity watchdog");end
endmodule
