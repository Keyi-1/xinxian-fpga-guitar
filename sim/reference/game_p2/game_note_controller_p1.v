`include "../config/game_score_config.vh"
// One serial score scan per sample; <= 2*128+overhead clocks is rejected by
// configuration. Current score has 67 events and finishes well within 256.
// Pluck times are captured in the audio domain; rendering never judges notes.
module game_note_controller_p1 #(
    parameter integer EVENT_COUNT=`GAME_EVENT_COUNT,
    parameter integer DURATION_SAMPLES=`GAME_DURATION_SAMPLES,
    parameter integer COUNTDOWN_SAMPLES=96000,
    parameter integer PERFECT_SAMPLES=1680,GOOD_SAMPLES=4320,WINDOW_SAMPLES=7200
)(input wire clk,rst_n,sample_tick,enable,start_song,demo,
  input wire [3:0] pluck_valid,input wire [7:0] velocity,
  output wire [3:0] note_on,note_off,
  output reg [127:0] target_phase,output reg [7:0] note_velocity,
  output wire [31:0] song_time,output reg countdown,finished,
  output reg [19:0] score,output reg [7:0] combo,max_combo,hits,misses,wrongs,
  output reg [11:0] judgement,output wire [127:0] consumed,
  output reg [7:0] judgement_epoch,
  output reg deadline_miss,output reg miss_event);
    localparam IDLE=0,READ=1,EVALUATE=2,COMMIT=3;
    reg [1:0] state;
    // Only real events need state bits. Zero-extend the published snapshot;
    // this also removes unused upper mask registers across the CDC/display.
    reg [EVENT_COUNT-1:0] consumed_bits;
    assign consumed={{(128-EVENT_COUNT){1'b0}},consumed_bits};
    // Runtime score times are 24 bits; only the published signed snapshot is
    // widened to 32 bits. Do not synthesize unused upper counter/mux bits.
    reg [23:0] elapsed;
    reg [16:0] countdown_left;
    reg [3:0] pending,scan_plucks,launch;
    reg [7:0] pending_velocity,scan_velocity;
    reg [95:0] pluck_times,scan_times;
    reg [23:0] end_time [0:3];
    reg [13:0] best_error [0:3];
    reg [6:0] best_index [0:3];
    reg [25:0] best_phase [0:3],next_phase [0:3];
    reg [23:0] best_duration [0:3],next_duration [0:3];
    reg [3:0] found,next_found;
    reg [6:0] address;
    wire [79:0] event_word;
    wire [1:0] lane=event_word[75:74];
    wire [23:0] on_time=event_word[23:0];
    wire [23:0] duration=event_word[47:24];
    wire [25:0] phase=event_word[73:48];
    wire signed [24:0] error_time=$signed({1'b0,scan_times[lane*24+:24]})-$signed({1'b0,on_time});
    wire [24:0] absolute_error=error_time[24] ? -error_time : error_time;
    wire eligible=scan_plucks[lane] && absolute_error<=WINDOW_SAMPLES;
    assign song_time=countdown ? -{15'd0,countdown_left} : {8'd0,elapsed};
    assign note_on=launch & {4{sample_tick && enable && !countdown}};
    genvar g;
    generate for(g=0;g<4;g=g+1)begin : ending
        assign note_off[g]=sample_tick && enable && !countdown && !note_on[g] && end_time[g]!=0 && elapsed>=end_time[g];
    end endgenerate
    game_score_rom_p1 u_rom(.clk(clk),.address(address),.event_word(event_word));
    integer i;
    reg [19:0] score_add;
    reg [7:0] hit_add,wrong_add,miss_add,combo_next,max_next;
    reg [3:0] launch_next;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;elapsed<=0;countdown_left<=0;countdown<=0;finished<=0;
            score<=0;combo<=0;max_combo<=0;hits<=0;misses<=0;wrongs<=0;judgement<=0;consumed_bits<=0;
            pending<=0;scan_plucks<=0;launch<=0;pending_velocity<=0;scan_velocity<=0;miss_event<=0;judgement_epoch<=0;
            pluck_times<=0;scan_times<=0;note_velocity<=0;found<=0;next_found<=0;address<=0;deadline_miss<=0;
            target_phase<={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};miss_add<=0;
            for(i=0;i<4;i=i+1)begin end_time[i]<=0;best_error[i]<=0;best_index[i]<=0;
                best_phase[i]<=0;best_duration[i]<=0;next_phase[i]<=0;next_duration[i]<=0;end
        end else if(start_song)begin
            state<=IDLE;elapsed<=0;countdown_left<=COUNTDOWN_SAMPLES;countdown<=COUNTDOWN_SAMPLES!=0;
            finished<=0;score<=0;combo<=0;max_combo<=0;hits<=0;misses<=0;wrongs<=0;judgement<=0;judgement_epoch<=0;
            consumed_bits<=0;pending<=0;launch<=0;deadline_miss<=0;miss_event<=0;
            for(i=0;i<4;i=i+1)end_time[i]<=0;
        end else if(!enable)begin state<=IDLE;pending<=0;launch<=0;miss_event<=0;end
        else begin
            miss_event<=0;
            // A four-lane batch is retained; no last-string mailbox overwrite.
            for(i=0;i<4;i=i+1)if(pluck_valid[i] && !countdown && !finished)begin
                pending[i]<=1;pending_velocity[i*2+:2]<=velocity[i*2+:2];pluck_times[i*24+:24]<=elapsed;
            end
            if(sample_tick)begin
                launch<=0;
                for(i=0;i<4;i=i+1)if(note_off[i])end_time[i]<=0;
                if(countdown)begin
                    if(countdown_left<=1)begin countdown<=0;countdown_left<=0;end
                    else countdown_left<=countdown_left-1'b1;
                end else if(!finished)begin
                    elapsed<=elapsed+1'b1;
                    if(elapsed>=DURATION_SAMPLES+WINDOW_SAMPLES)finished<=1;
                    if(state!=IDLE)deadline_miss<=1;
                    else begin
                        scan_plucks<=pending|pluck_valid;scan_velocity<=pending_velocity;scan_times<=pluck_times;
                        for(i=0;i<4;i=i+1)begin
                            if(pluck_valid[i])begin scan_velocity[i*2+:2]<=velocity[i*2+:2];scan_times[i*24+:24]<=elapsed;end
                            best_error[i]<=14'h3fff;
                        end
                        pending<=0;found<=0;next_found<=0;address<=0;state<=READ;miss_add<=0;
                    end
                end
            end
            case(state)
                READ:state<=EVALUATE;
                EVALUATE:begin
                    if(!consumed_bits[address])begin
                        if(demo && on_time<=elapsed)begin
                            found[lane]<=1;best_index[lane]<=address;best_phase[lane]<=phase;best_duration[lane]<=duration;
                        end else if(!demo && eligible && absolute_error<best_error[lane])begin
                            found[lane]<=1;best_error[lane]<=absolute_error[13:0];best_index[lane]<=address;
                            best_phase[lane]<=phase;best_duration[lane]<=duration;
                        end
                        if(!demo && elapsed>on_time+WINDOW_SAMPLES && !eligible)begin
                            consumed_bits[address]<=1;miss_add<=miss_add+1'b1;judgement[lane*3+:3]<=4;
                            judgement_epoch[lane*2+:2]<=judgement_epoch[lane*2+:2]+1'b1;
                        end
                        if(!next_found[lane] && on_time>=elapsed && on_time<=elapsed+48000)begin
                            next_found[lane]<=1;next_phase[lane]<=phase;next_duration[lane]<=duration;
                        end
                    end
                    if(address==EVENT_COUNT-1)state<=COMMIT;
                    else begin address<=address+1'b1;state<=READ;end
                end
                COMMIT:begin
                    miss_event<=miss_add!=0 && !demo;
                    score_add=0;hit_add=0;wrong_add=0;combo_next=miss_add!=0 ? 8'd0 : combo;max_next=max_combo;launch_next=0;
                    for(i=0;i<4;i=i+1)begin
                        if(found[i])begin
                            consumed_bits[best_index[i]]<=1;target_phase[i*32+:32]<=best_phase[i];
                            end_time[i]<=elapsed+best_duration[i];launch_next[i]=1;
                            note_velocity[i*2+:2]<=demo ? 2'd2 : scan_velocity[i*2+:2];
                            if(!demo)begin
                                judgement_epoch[i*2+:2]<=judgement_epoch[i*2+:2]+1'b1;
                                hit_add=hit_add+1'b1;
                                if(best_error[i]<=PERFECT_SAMPLES)begin score_add=score_add+100;combo_next=combo_next+1'b1;judgement[i*3+:3]<=1;end
                                else if(best_error[i]<=GOOD_SAMPLES)begin score_add=score_add+70;combo_next=combo_next+1'b1;judgement[i*3+:3]<=2;end
                                else begin score_add=score_add+25;combo_next=0;judgement[i*3+:3]<=3;end
                                if(combo_next>max_next)max_next=combo_next;
                            end
                        end else if(scan_plucks[i] && !demo)begin
                            judgement_epoch[i*2+:2]<=judgement_epoch[i*2+:2]+1'b1;
                            wrong_add=wrong_add+1'b1;combo_next=0;judgement[i*3+:3]<=5;launch_next[i]=1;
                            note_velocity[i*2+:2]<=scan_velocity[i*2+:2];end_time[i]<=elapsed+(next_found[i] ? next_duration[i] : 32'd14400);
                            target_phase[i*32+:32]<=next_found[i] ? next_phase[i] :
                                i==0 ? 32'h01c20d2f : i==1 ? 32'h0151285d : i==2 ? 32'h010b9a2b : 32'h00c879a3;
                        end
                    end
                    launch<=launch_next;score<=score+score_add;hits<=hits+hit_add;
                    misses<=misses+miss_add;wrongs<=wrongs+wrong_add;combo<=combo_next;max_combo<=max_next;state<=IDLE;
                end
            endcase
        end
    end
endmodule
