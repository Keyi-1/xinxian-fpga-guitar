module game_font_rom(input wire clk,input wire [6:0] glyph,input wire [3:0] row,
    output reg [15:0] bits);
    reg [15:0] memory [0:2047];
    initial $readmemh("../../mem/game_font_16.mem",memory);
    always @(posedge clk)bits<=memory[{glyph,row}];
endmodule
