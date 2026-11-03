`timescale 1ns/1ps
module tb_piano_mode_state_ram;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg read_enable=0,read_gain=0,phase_write=0,gain_write=0;reg [4:0] address=0;
    reg [31:0] phase_data=0;reg [23:0] gain_data=0;
    wire [31:0] phase_q;wire [23:0] gain_q;
    piano_mode_state_ram dut(.*);
    `include "piano_mode_ram_checks.vh"
endmodule
