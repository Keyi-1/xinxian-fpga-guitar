// System port arbitration belongs to the import owner. Writes only target
// unpublished space, while both playback ports retain their one-cycle latency.
module game_p3_score_bank(
    input wire audio_clk,audio_read,input wire [10:0] audio_address,
    output wire [95:0] audio_data,
    input wire display_clk,display_read,input wire [10:0] display_address,
    output wire [95:0] display_data,
    input wire write_enable,input wire [10:0] write_address,
    input wire [95:0] write_data);
    wire [95:0] audio_low,audio_high,display_low,display_high;
    reg audio_page=0,display_page=0;
    wire [10:0] system_address=write_enable ? write_address : display_address;
    always @(posedge audio_clk)if(audio_read)audio_page<=audio_address[10];
    always @(posedge display_clk)if(display_read && !write_enable)display_page<=display_address[10];
    assign audio_data=audio_page ? audio_high : audio_low;
    assign display_data=display_page ? display_high : display_low;
    `include "../config/game_p3_bsram_init.vh"
endmodule
