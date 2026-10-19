`timescale 1ns/1ps
module tb_first_string_crosstalk;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0;reg [1:0] channel=0;reg [11:0] data=2053;
    wire [3:0] events,old_events,pending,old_pending;
    wire [7:0] velocity,old_velocity;
    integer counts[0:3];integer old_count0=0,trial=0,c,j,polarity,amplitude;
    four_string_pluck_detector dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),
      .sample_string(channel),.sample_data(data),.pluck_valid(events),.velocity_level(velocity),
      .raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(pending));
    // Independently retain the previous trigger while all other parameters match.
    four_string_pluck_detector #(.TRIGGER_THRESHOLD_CH0(150)) previous(.clk(clk),.rst_n(rst_n),.sample_valid(valid),
      .sample_string(channel),.sample_data(data),.pluck_valid(old_events),.velocity_level(old_velocity),
      .raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(old_pending));
    always @(posedge clk)begin
      #1;
      if(rst_n)begin
        if({events[3:1],pending[3:1],velocity[7:2]}!=={old_events[3:1],old_pending[3:1],old_velocity[7:2]})
          $fatal(1,"FAIL: CH0 adjustment affected another channel");
        for(integer n=0;n<4;n=n+1)if(events[n])counts[n]=counts[n]+1;
        if(old_events[0])old_count0=old_count0+1;
      end
    end
    task feed(input integer ch,raw);
      @(negedge clk);valid=1;channel=ch;data=raw;
      @(negedge clk);valid=0;
    endtask
    task reset;
      @(negedge clk);rst_n=0;valid=0;repeat(2)@(negedge clk);
      for(integer n=0;n<4;n=n+1)counts[n]=0;
      old_count0=0;rst_n=1;
    endtask
    initial begin
      // Synthetic shared-body pickup: other strings attack while CH0 sees
      // sustained bipolar deviations that used to trigger it. No hardware claim.
      for(polarity=-1;polarity<=1;polarity=polarity+2)
      for(amplitude=150;amplitude<220;amplitude=amplitude+1)begin
        reset();
        for(j=0;j<40;j=j+1)begin
          feed(0,2053+polarity*amplitude);
          for(c=1;c<4;c=c+1)feed(c,2853);
        end
        if(counts[0]!=0 || pending[0]!=0 || old_count0!=1)
          $fatal(1,"FAIL: old-trigger-only pickup not rejected amplitude%0d",amplitude);
        for(c=1;c<4;c=c+1)if(counts[c]!=1)$fatal(1,"FAIL: lost another string");
        // A genuine CH0 attack at the new boundary still plays the lowest grade,
        // even while the other three strings are in their refractory periods.
        feed(0,2053+polarity*220);repeat(32)feed(0,2053);
        if(counts[0]!=1 || velocity[1:0]!=0 || pending[0]!=0)
          $fatal(1,"FAIL: genuine CH0 boundary attack blocked");
        trial=trial+1;
      end
      $display("PASS: CH0-only threshold220,140 bipolar pickup scenarios150..219 suppressed vs previous150; CH1..3 event/grade/pending cycle-equivalent; real boundary220 grade0 accepted with other strings active");$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: crosstalk watchdog");end
endmodule
