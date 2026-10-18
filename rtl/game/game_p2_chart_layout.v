`include "../config/game_score_config.vh"
// Positions come from absolute 48 kHz song time. One serial constant divider
// is reused for centres and duration tails, entirely during vertical blank.
module game_p2_chart_layout #(parameter integer WRITABLE=0)(input wire clk,rst_n,frame_start,snapshot_update,
    input wire [4:0] overlay_valid,input wire [479:0] overlay_data,
    input wire [255:0] snapshot,
    output wire score_read,output wire [10:0] score_address,input wire [95:0] score_data,
    output wire [383:0] centres,output wire [287:0] tails,
    output reg [31:0] valid_blocks,output wire [255:0] display_snapshot,
    output reg overflow,deadline_miss);
    localparam IDLE=0,READ=1,EVALUATE=2,DIVIDE_X=3,DIVIDE_TAIL=4,NEXT=5,WAIT=6;
    reg [2:0] state;
    reg [11:0] address,limit;
    wire [95:0] event_word=score_data;
    wire [1:0] lane=event_word[72:71];
    wire [10:0] base,static_base;wire [11:0] event_count,static_count;
    assign base=static_base;
    assign event_count=static_count;
    reg [5:0] previous_generation;
    generate if(WRITABLE)begin:runtime_catalog
    game_p3_catalog catalog(.slot(snapshot[237:235]),.overlay_valid(overlay_valid),.overlay_data(overlay_data),
        .valid(),.playable(),.test_only(),.timbre(),.duration(),.progress_step(),.base(static_base),.event_count(static_count));
    end else begin:immutable_catalog
    game_p2_catalog catalog(.slot(snapshot[237:235]),.valid(),.playable(),.test_only(),.timbre(),.duration(),.base(static_base),.event_count(static_count));
    end endgenerate
    assign score_read=state==READ;
    assign score_address=base+address[10:0];
    // game_snapshot_cdc already holds this word until the next frame request.
    // Reuse that coherent destination bank during layout and active video;
    // copying it twice here wastes registers and routing at nearly full CLS.
    // Contract: snapshot changes only with snapshot_update in vertical blank,
    // and remains stable until the next frame's layout pass.
    wire [255:0] held=snapshot;
    assign display_snapshot=snapshot;
    wire signed [32:0] delta=$signed({1'b0,event_word[31:0]})-$signed({held[95],held[95:64]});
    // The pass starts just after frame_start and finishes before active video.
    // Update one coordinate bank in blank; a second 672-bit bank is redundant.
    reg [11:0] front_x[0:31];
    reg [8:0] front_tail[0:31];
    // Four explicit counters: Gowin's inferred multi-write array did not
    // clear every lane on a new pass in the synthesized netlist.
    reg [3:0] count0,count1,count2,count3;
    wire [3:0] lane_count=lane==0 ? count0 : lane==1 ? count1 : lane==2 ? count2 : count3;
    reg [31:0] back_valid;
    reg [4:0] slot;reg [5:0] bit_count;
    reg [17:0] dividend,quotient,duration;
    reg [8:0] remainder;
    wire [9:0] trial={remainder,dividend[17]};
    wire subtract=trial>=250;
    wire [17:0] next_quotient={quotient[16:0],subtract};
    reg negative;

    genvar g;
    generate for(g=0;g<32;g=g+1)begin : outputs
        assign centres[g*12+:12]=front_x[g];assign tails[g*9+:9]=front_tail[g];
    end endgenerate
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;address<=0;limit<=0;previous_generation<=0;back_valid<=0;valid_blocks<=0;
            overflow<=0;deadline_miss<=0;slot<=0;bit_count<=0;dividend<=0;quotient<=0;duration<=0;remainder<=0;negative<=0;
            for(i=0;i<32;i=i+1)begin front_x[i]<=0;front_tail[i]<=0;end
            count0<=0;count1<=0;count2<=0;count3<=0;
        end else begin
            if(frame_start && state!=IDLE && state!=WAIT)deadline_miss<=1;
            case(state)
                IDLE:if(snapshot_update)begin
                    back_valid<=0;address<=held[249:238];
                    limit<=event_count-held[249:238]>64 ? held[249:238]+12'd64 : event_count;
                    state<=held[229:228]<2 || held[249:238]>=event_count ? WAIT : READ;
                    if(previous_generation!=held[255:250])begin overflow<=0;deadline_miss<=0;end
                    previous_generation<=held[255:250];
                    count0<=0;count1<=0;count2<=0;count3<=0;
                end
                READ:state<=EVALUATE;
                EVALUATE:begin
                    if(!held[address[5:0]] && delta<=101000 && delta>=-7200)begin
                        if(lane_count>=8)begin overflow<=1;state<=NEXT;end
                        else begin
                            slot<={lane,3'd0}+lane_count;
                            case(lane)
                                0:count0<=count0+1'b1;
                                1:count1<=count1+1'b1;
                                2:count2<=count2+1'b1;
                                3:count3<=count3+1'b1;
                            endcase
                            dividend<=(delta[32] ? -delta : delta)+125;negative<=delta[32];
                            duration<=event_word[63:32]>80000 ? 18'd80000 : event_word[49:32];quotient<=0;remainder<=0;bit_count<=17;state<=DIVIDE_X;
                        end
                    end else state<=NEXT;
                end
                DIVIDE_X,DIVIDE_TAIL:begin
                    dividend<={dividend[16:0],1'b0};quotient<=next_quotient;
                    remainder<=subtract ? trial-250 : trial;
                    if(bit_count==0)begin
                        if(state==DIVIDE_X)begin
                            front_x[slot]<=negative ? 12'd96-next_quotient[11:0] : 12'd96+next_quotient[11:0];
                            dividend<=duration;quotient<=0;remainder<=0;bit_count<=17;state<=DIVIDE_TAIL;
                        end else begin
                            front_tail[slot]<=next_quotient>320 ? 9'd320 : next_quotient[8:0];
                            back_valid[slot]<=1;state<=NEXT;
                        end
                    end else bit_count<=bit_count-1'b1;
                end
                NEXT:if(address+1'b1>=limit)state<=WAIT;
                     else begin address<=address+1'b1;state<=READ;end
                // The request is issued at frame_start and this serial pass
                // finishes inside vertical blank. Publish in the SAME blank,
                // avoiding an extra frame of motion latency at the hit line.
                WAIT:begin
                    valid_blocks<=back_valid;state<=IDLE;
                end
            endcase
        end
    end
endmodule
