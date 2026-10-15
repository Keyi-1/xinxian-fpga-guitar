// Explicit 16-bit DPB slices avoid the inferred wide-ROM initializer's
// compacted-word packing error (observed MIDI 59 -> 29 at address 1).
// Twelve true dual-port blocks retain all 2048 x 96 bits, including group IDs.
// Both ports use normal one-cycle reads; there are no runtime writes.
module game_p2_score_bank(input wire audio_clk,audio_read,
    input wire [10:0] audio_address,output wire [95:0] audio_data,
    input wire display_clk,display_read,
    input wire [10:0] display_address,output wire [95:0] display_data);
    wire [95:0] audio_low,audio_high,display_low,display_high;
    reg audio_page=0,display_page=0;
    always @(posedge audio_clk)if(audio_read)audio_page<=audio_address[10];
    always @(posedge display_clk)if(display_read)display_page<=display_address[10];
    assign audio_data=audio_page ? audio_high : audio_low;
    assign display_data=display_page ? display_high : display_low;
    `include "../config/game_p2_bsram_init.vh"
endmodule
