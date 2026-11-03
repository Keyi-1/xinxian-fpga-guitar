`timescale 1ns/1ps
// Actual complete VG's gain-ROM module, driven only through audited ports.
module tb_game_p3_rock_gain_gate;
    GSR GSR(.GSRI(1'b1));
    `include "rock_coeffs.vh"
    reg clk=0;always #5 clk=~clk;
    reg read_enable=0;reg [6:0] address=0;wire [15:0] gain_data;
    `include "p3_gate_gain.vh"
    integer i,j,reads=0;reg [15:0] held;
    initial begin
        for(j=0;j<2;j=j+1)for(i=0;i<128;i=i+1)begin
            @(negedge clk);address=j==0 ? i : 127-i;read_enable=1;
            @(posedge clk);#1;
            if(gain_data!==rock_gain_for(address[6:5],address[4:0]))$fatal(1,"FAIL: actual gain ROM entry%0d",address);
            held=gain_data;reads=reads+1;
            @(negedge clk);read_enable=0;address=~address;
            repeat(3)begin @(posedge clk);#1;
                if(gain_data!==held)$fatal(1,"FAIL: actual gain ROM read-enable hold");end
        end
        $display("PASS: actual complete VG gain ROM %0d reads, all128 constants/defaults forward/reverse, one-clock read and enable hold; audited physical DPB address/read/clock/data ports; no internal force",reads);
        $finish;
    end
    initial begin #100000;$fatal(1,"FAIL: actual gain ROM watchdog");end
endmodule
