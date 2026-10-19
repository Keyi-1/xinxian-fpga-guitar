`timescale 1ns/1ps
module tb_velocity_adc_gate;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #40.690104 clk=~clk;
    reg rst_n=0;reg [47:0] values={4{12'd2053}};
    wire gcs,gmosi,gsclk,gmiso,rcs,rmosi,rsclk,rmiso;
    wire [3:0] gpluck,rpluck,gpending,rpending;wire [7:0] gvelocity,rvelocity;
    wire [31:0] gcount,rcount;integer c,g,events=0,before_events,clocks=0;
    `include "velocity_gate_adc.vh"
    rtlref_mcp3208_pluck_frontend reference(.clk(clk),.rst_n(rst_n),.adc_cs_n(rcs),.adc_sclk(rsclk),
      .adc_mosi(rmosi),.adc_miso(rmiso),.pluck_valid(rpluck),.velocity_level(rvelocity),.raw_adc(),.peak_adc(),.event_timestamp(),.capture_pending(rpending));
    mcp3208_test_slave gate_chip(.rst_n(rst_n),.cs_n(gcs),.sclk(gsclk),.mosi(gmosi),.values(values),.miso(gmiso),.conversions(gcount));
    mcp3208_test_slave ref_chip(.rst_n(rst_n),.cs_n(rcs),.sclk(rsclk),.mosi(rmosi),.values(values),.miso(rmiso),.conversions(rcount));
    always @(posedge clk)begin
      #2;
      if(rst_n)begin
        clocks=clocks+1;
        if({gcs,gmosi,gsclk,gpluck,gvelocity,gpending}!=={rcs,rmosi,rsclk,rpluck,rvelocity,rpending})
          $fatal(1,"FAIL: actual VG ADC differs c%0d g%0d at%0t",c,g,$time);
        if(gpluck)begin
          if(gpluck!==(1<<c) || gvelocity[c*2+:2]!==g[1:0])$fatal(1,"FAIL: actual VG calibrated grade");
          events=events+1;
        end
      end
    end
    function integer raw(input integer ch,level);
      case(ch)
        0:case(level)0:raw=2273;1:raw=2333;2:raw=2483;3:raw=2673;endcase
        1:case(level)0:raw=2153;1:raw=2303;2:raw=2453;3:raw=2653;endcase
        2:case(level)0:raw=2133;1:raw=2203;2:raw=2333;3:raw=2453;endcase
        3:case(level)0:raw=2153;1:raw=2273;2:raw=2433;3:raw=2653;endcase
      endcase
    endfunction
    initial begin
      repeat(10)@(negedge clk);rst_n=1;
      for(c=0;c<4;c=c+1)for(g=0;g<4;g=g+1)begin
        values={4{12'd2053}};repeat(260000)@(negedge clk);
        before_events=events;values[c*12+:12]=raw(c,g);
        wait(events>before_events);repeat(800)@(negedge clk);
        if(events!=before_events+1)$fatal(1,"FAIL: actual VG spurious retrigger");
      end
      values={4{12'd2053}};repeat(260000)@(negedge clk);
      if(events!=16 || gcount!=rcount)$fatal(1,"FAIL: actual ADC count");
      $display("PASS: actual complete VG ADC frontend vs RTL, all4 strings x4 grades,production SPI4/capture32/dead400/settle80,8 velocity+4 pending bits,exact GPIO/cycle compare; %0d clocks/%0d conversions,zero forces",clocks,gcount);$finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: ADC gate watchdog");end
endmodule
