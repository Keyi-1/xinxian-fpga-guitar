// Replace a large combinational message case tree with one synchronous ROM.
// Its output shares the first pixel stage with row/column and digit registers.
module game_message_rom(input wire clk,input wire [9:0] address,output reg [6:0] glyph);
    reg [6:0] memory[0:1023];
    initial $readmemh("../../mem/game_message_index.mem",memory);
    always @(posedge clk)glyph<=memory[address];
endmodule
