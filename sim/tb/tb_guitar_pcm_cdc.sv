`timescale 1ns/1ps
module tb_guitar_pcm_cdc;
    reg a=0,b=0,rst=0,valid=0;
    always #40.690104 a=~a;
    always #10 b=~b;
    reg signed [23:0] pcm=0;
    wire dv,overrun;
    wire signed [23:0] received;
    guitar_pcm_cdc dut(.src_clk(a),.src_rst_n(rst),.src_valid(valid),.src_pcm(pcm),
        .dst_clk(b),.dst_rst_n(rst),.dst_valid(dv),.dst_pcm(received),.overrun(overrun));
    reg [23:0] expected[0:1999];
    integer n=0,copies=0;
    always @(posedge b)begin #1;if(dv)begin
        if(received!==expected[copies])$fatal(1,"FAIL: torn/reordered PCM %0d",copies);
        copies++;
    end end
    initial begin
        repeat(5)@(negedge a);rst=1;
        for(n=0;n<2000;n++)begin
            @(negedge a);expected[n]=$random;pcm=expected[n];valid=1;
            @(negedge a);valid=0;repeat(254)@(negedge a);
        end
        repeat(20)@(negedge b);
        if(copies!=2000 || overrun)$fatal(1,"FAIL: PCM missing or overrun");
        $display("PASS: 2000 atomic PCM24 transfers at 48 kHz, independent 12.288/50 MHz clocks, no overrun");$finish;
    end
endmodule
