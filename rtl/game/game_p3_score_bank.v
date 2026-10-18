// System port arbitration belongs to the import owner. Writes only target
// unpublished space, while both playback ports retain their one-cycle latency.
module game_p3_score_bank(
    input wire audio_clk,audio_read,input wire [10:0] audio_address,
    output wire [95:0] audio_data,
    input wire display_clk,display_read,input wire [10:0] display_address,
    output wire [95:0] display_data,
    input wire write_enable,input wire [10:0] write_address,
    input wire [95:0] write_data);
    // Legal records carry 77 nonconstant bits: two25-bit times,7-bit MIDI,
    // two-bit lane/velocity and full16-bit group. Validation rejects all
    // omitted bits before writing. Reconstruct the exact logical96-bit word.
    reg audio_page=0,display_page=0;
    wire [79:0] audio_low,audio_high,display_low,display_high;
    wire [79:0] packed_write={3'd0,write_data[95:80],write_data[74:64],
                             write_data[56:32],write_data[24:0]};
    wire [79:0] audio_packed=audio_page ? audio_high : audio_low;
    wire [79:0] display_packed=display_page ? display_high : display_low;
    wire [10:0] system_address=write_enable ? write_address : display_address;
    always @(posedge audio_clk)if(audio_read)audio_page<=audio_address[10];
    always @(posedge display_clk)if(display_read && !write_enable)display_page<=display_address[10];
    assign audio_data={audio_packed[76:61],5'd0,audio_packed[60:50],
                       7'd0,audio_packed[49:25],7'd0,audio_packed[24:0]};
    assign display_data={display_packed[76:61],5'd0,display_packed[60:50],
                         7'd0,display_packed[49:25],7'd0,display_packed[24:0]};
    `include "../config/game_p3_bsram_init.vh"
endmodule
