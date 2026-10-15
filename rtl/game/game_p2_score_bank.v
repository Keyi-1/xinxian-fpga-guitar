// Static dual-clock, read-only P2 score bank. One-cycle synchronous reads.
// RAM primitive count/mapping must be checked at integration synthesis.
// Published immutable data makes old frame descriptors safe during a new scan.
module game_p2_score_bank(input wire audio_clk,audio_read,
    input wire [10:0] audio_address,output reg [95:0] audio_data,
    input wire display_clk,display_read,
    input wire [10:0] display_address,output reg [95:0] display_data);
    reg [95:0] memory[0:2047];
    initial $readmemh("../../mem/game_p2_static.mem",memory);
    always @(posedge audio_clk)if(audio_read)audio_data<=memory[audio_address];
    always @(posedge display_clk)if(display_read)display_data<=memory[display_address];
endmodule
