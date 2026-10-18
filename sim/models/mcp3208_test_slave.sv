`timescale 1ns/1ps
// Pin-level MCP3208 stimulus; reports the requested channel and conversion count.
module mcp3208_test_slave(input wire rst_n,cs_n,sclk,mosi,
    input wire [47:0] values,output reg miso=0,output reg [31:0] conversions=0);
    reg [4:0] command=0;reg [2:0] channel=0;reg [11:0] data=0;integer bits=0;
    always @(negedge cs_n)begin command=0;channel=0;data=0;bits=0;miso=0;end
    always @(posedge sclk)if(rst_n && !cs_n)begin
        if(bits<5)command[4-bits]=mosi;
        if(bits==4)begin
            if(command[4:3]!==2'b11 || command[2:0]>3)$fatal(1,"FAIL: ADC command/channel");
            channel=command[2:0];data=values[channel*12+:12];conversions=conversions+1;
        end
        bits=bits+1;
    end
    always @(negedge sclk)if(rst_n && !cs_n)begin
        if(bits>=7 && bits<=18)miso=data[18-bits];else miso=0;
    end
endmodule
