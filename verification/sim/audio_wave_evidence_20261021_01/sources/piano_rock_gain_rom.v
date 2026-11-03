// Read in LOAD, five clocks before LOOKUP consumes this gain. No added state,
// sample latency or modal schedule. All96 constants match rock_gain_for.
module piano_rock_gain_rom(input wire clk,read_enable,input wire [6:0] address,
    output wire [15:0] data);
    `include "piano_rock_gain_init.vh"
endmodule
