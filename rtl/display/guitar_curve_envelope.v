// Display only: independent per-voice brightness, committed in vertical blank.
// Full attack on an accepted pluck, fast peak following, slow release toward
// the measured PCM level. Eight display frames fade the last audible shape
// after a voice ends (149 ms at the panel's 53.745 Hz refresh rate).
// Shifts/adds only: no RAM, divider or multiplier.
module guitar_curve_envelope(input wire clk,rst_n,visual_update,
    input wire [3:0] voice_active,input wire [15:0] level,
    input wire [31:0] strikes,output reg [31:0] gain,
    output wire [3:0] curve_active);
    reg [31:0] old_strikes;
    reg [3:0] tail_frames [0:3];
    reg [7:0] tail_step [0:3];
    reg [7:0] target;
    reg [8:0] difference,step;
    integer i;
    genvar g;
    generate for(g=0;g<4;g=g+1)begin : visible
        assign curve_active[g]=|gain[g*8+2+:6];
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            gain<=0;old_strikes<=0;
            for(i=0;i<4;i=i+1)begin tail_frames[i]<=0;tail_step[i]<=0;end
        end else if(visual_update)begin
            old_strikes<=strikes;
            for(i=0;i<4;i=i+1)begin
                target={level[i*4+:4],4'd0};
                if(strikes[i*8+:8]!=old_strikes[i*8+:8])begin
                    gain[i*8+:8]<=255;tail_frames[i]<=0;
                end else if(voice_active[i])begin
                    tail_frames[i]<=0;
                    if(target>gain[i*8+:8])begin
                        difference={1'b0,target}-{1'b0,gain[i*8+:8]};
                        step=(difference+9'd1)>>1;
                        gain[i*8+:8]<=gain[i*8+:8]+step[7:0];
                    end else if(target<gain[i*8+:8])begin
                        difference={1'b0,gain[i*8+:8]}-{1'b0,target};
                        step=(difference+9'd31)>>5;
                        gain[i*8+:8]<=gain[i*8+:8]-step[7:0];
                    end
                end else if(gain[i*8+:8]!=0)begin
                    if(tail_frames[i]==0)begin
                        step=({1'b0,gain[i*8+:8]}+9'd7)>>3;
                        tail_step[i]<=step[7:0];tail_frames[i]<=7;
                        gain[i*8+:8]<=gain[i*8+:8]-step[7:0];
                    end else begin
                        tail_frames[i]<=tail_frames[i]-1'b1;
                        if(tail_frames[i]==1 || gain[i*8+:8]<=tail_step[i])
                            gain[i*8+:8]<=0;
                        else gain[i*8+:8]<=gain[i*8+:8]-tail_step[i];
                    end
                end
            end
        end
    end
endmodule
