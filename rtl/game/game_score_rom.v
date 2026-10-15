// Synchronous score memory. Two readers are separate small ROM instances;
// neither can stall the 48 kHz sound path.
module game_score_rom(input wire clk,input wire [6:0] address,
    output reg [79:0] event_word);
    reg [79:0] memory [0:127];
    initial $readmemh("../../mem/jasmine_game.mem",memory);
    always @(posedge clk)event_word<=memory[address];
endmodule
