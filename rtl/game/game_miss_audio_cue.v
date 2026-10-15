// A quiet 30 ms, 750 Hz triangular UI cue, mixed after musical effects.
// It owns no musical voice, note event, DSP, RAM or recording.
module game_miss_audio_cue #(
    parameter integer LENGTH_SAMPLES=1440
)(input wire clk,rst_n,sample_valid,enabled,trigger,
  input wire signed [23:0] left_in,right_in,
  output wire signed [23:0] left_out,right_out);
    reg pending;
    reg [10:0] remaining;
    reg [4:0] attack;
    reg [5:0] phase;
    wire signed [7:0] twice_phase=$signed({1'b0,phase,1'b0});
    wire signed [7:0] triangle=phase[5] ? 8'sd95-twice_phase : twice_phase-8'sd31;
    wire signed [23:0] amplitude=$signed({{4{triangle[6]}},triangle[6:0],13'd0});
    wire [2:0] attack_shift=attack<2 ? 4 : attack<4 ? 3 : attack<8 ? 2 : attack<16 ? 1 : 0;
    wire [2:0] release_shift=remaining<16 ? 4 : remaining<32 ? 3 : remaining<64 ? 2 : remaining<128 ? 1 : 0;
    wire [2:0] attenuation=attack_shift>release_shift ? attack_shift : release_shift;
    wire sounding=enabled && remaining!=0;
    wire signed [23:0] cue=sounding ? amplitude >>> attenuation : 24'sd0;
    wire signed [24:0] left_sum=$signed({left_in[23],left_in})+$signed({cue[23],cue});
    wire signed [24:0] right_sum=$signed({right_in[23],right_in})+$signed({cue[23],cue});
    assign left_out=!sounding ? left_in : left_sum[24]==left_sum[23] ? left_sum[23:0] :
        left_sum[24] ? 24'sh800000 : 24'sh7fffff;
    assign right_out=!sounding ? right_in : right_sum[24]==right_sum[23] ? right_sum[23:0] :
        right_sum[24] ? 24'sh800000 : 24'sh7fffff;
    always @(posedge clk)begin
        if(!rst_n || !enabled)begin pending<=0;remaining<=0;attack<=0;phase<=0;end
        else begin
            if(trigger)pending<=1;
            if(sample_valid)begin
                if(pending || trigger)begin
                    pending<=0;remaining<=LENGTH_SAMPLES;attack<=0;phase<=0;
                end else if(remaining!=0)begin
                    remaining<=remaining-1'b1;phase<=phase+1'b1;
                    if(attack<16)attack<=attack+1'b1;
                end
            end
        end
    end
endmodule
