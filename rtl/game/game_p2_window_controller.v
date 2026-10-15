// P2 bounded engine: at most 64 events plus one density guard, independent of song
// length. Immutable score reads have one-clock latency. No per-song bit mask.
// Used by game_p2_mode_router; faults require sustain-independent release.
module game_p2_window_controller #(
    parameter integer COUNTDOWN_SAMPLES=96000,
    parameter integer PERFECT_SAMPLES=1680,GOOD_SAMPLES=4320,WINDOW_SAMPLES=7200,
    parameter integer DISPLAY_AHEAD_SAMPLES=101000
)(input wire clk,rst_n,sample_tick,enable,start_song,demo,
  input wire catalog_valid,input wire [10:0] catalog_base,
  input wire [11:0] catalog_count,input wire [31:0] catalog_duration,
  input wire [3:0] pluck_valid,input wire [7:0] velocity,
  output wire read_enable,output wire [10:0] read_address,input wire [95:0] read_data,
  output wire [3:0] note_on,note_off,
  output reg [127:0] target_phase,output reg [7:0] note_velocity,
  output wire [31:0] song_time,output reg countdown,finished,fault,deadline_miss,
  output reg [3:0] fault_code,output reg miss_event,snapshot_valid,
  output reg [31:0] score,output reg [15:0] combo,max_combo,hits,misses,wrongs,
  output reg [11:0] judgement,output reg [7:0] judgement_epoch,
  output reg [11:0] window_head,output wire [6:0] window_count,
  output reg [63:0] consumed_snapshot,output reg [15:0] generation);
    localparam IDLE=0,READ=1,EVALUATE=2,COMMIT=3;
    reg [1:0] state;
    reg [10:0] base;
    reg [11:0] count,scan_id,scan_begin,scan_end,retire_head;
    reg [31:0] duration_limit,elapsed,countdown_left,previous_onset;
    reg retire_open;
    reg [63:0] consumed_bits;
    reg [3:0] pending,scan_plucks,launch,found,next_found;
    reg [7:0] pending_velocity,scan_velocity;
    reg [127:0] pluck_times,scan_times;
    reg [31:0] end_time[0:3],best_duration[0:3],next_duration[0:3];
    reg [13:0] best_error[0:3];
    reg [5:0] best_slot[0:3];
    reg [25:0] best_phase[0:3],next_phase[0:3];
    reg [6:0] miss_add;
    wire [31:0] onset=read_data[31:0],duration=read_data[63:32];
    wire [6:0] midi=read_data[70:64];
    wire [1:0] lane=read_data[72:71];
    wire probe=scan_id==scan_begin+12'd64;
    wire signed [32:0] error_time=$signed({1'b0,scan_times[lane*32+:32]})-$signed({1'b0,onset});
    wire [32:0] absolute_error=error_time[32] ? -error_time : error_time;
    wire eligible=scan_plucks[lane] && absolute_error<=WINDOW_SAMPLES;
    wire expired=!demo && {1'b0,elapsed}>{1'b0,onset}+WINDOW_SAMPLES && !eligible;
    wire invalid_word=midi<50 || midi>72 || duration==0 || read_data[79:75]!=0 ||
        {1'b0,onset}+{1'b0,duration}>{1'b0,duration_limit} ||
        (scan_id!=scan_begin && onset<previous_onset);
    assign read_enable=state==READ && enable && !fault && !start_song;
    assign read_address=base+scan_id[10:0];
    assign window_count=count-window_head>64 ? 7'd64 : count-window_head;
    assign song_time=countdown ? -countdown_left : elapsed;
    assign note_on=launch & {4{sample_tick && enable && !countdown && !finished && !fault}};
    genvar g;
    generate for(g=0;g<4;g=g+1)begin: ending
        assign note_off[g]=sample_tick && enable && !countdown && !note_on[g] &&
            end_time[g]!=0 && elapsed>=end_time[g];
    end endgenerate
    function [25:0] midi_phase;
        input [6:0] midi;
        begin
            `include "../config/game_p2_phase.vh"
        end
    endfunction
    function [15:0] add16;
        input [15:0] a;input [6:0] b;
        reg [16:0] sum;
        begin sum={1'b0,a}+b;add16=sum[16] ? 16'hffff : sum[15:0];end
    endfunction
    integer i;
    reg [63:0] commit_bits;
    reg [9:0] score_add;
    reg [6:0] hit_add,wrong_add;
    reg [15:0] combo_next,max_next;
    reg [32:0] score_next;
    reg [3:0] launch_next;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;base<=0;count<=0;scan_id<=0;scan_begin<=0;scan_end<=0;retire_head<=0;retire_open<=0;
            duration_limit<=0;elapsed<=0;countdown_left<=0;previous_onset<=0;
            countdown<=0;finished<=0;fault<=0;fault_code<=0;deadline_miss<=0;
            consumed_bits<=0;consumed_snapshot<=0;window_head<=0;generation<=0;
            pending<=0;scan_plucks<=0;launch<=0;found<=0;next_found<=0;
            pending_velocity<=0;scan_velocity<=0;pluck_times<=0;scan_times<=0;
            note_velocity<=0;miss_add<=0;miss_event<=0;snapshot_valid<=0;
            score<=0;combo<=0;max_combo<=0;hits<=0;misses<=0;wrongs<=0;judgement<=0;judgement_epoch<=0;
            target_phase<={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
            for(i=0;i<4;i=i+1)begin end_time[i]<=0;best_error[i]<=0;best_slot[i]<=0;
                best_phase[i]<=0;best_duration[i]<=0;next_phase[i]<=0;next_duration[i]<=0;end
        end else if(start_song)begin
            state<=IDLE;base<=catalog_base;count<=catalog_count;duration_limit<=catalog_duration;
            elapsed<=0;countdown_left<=COUNTDOWN_SAMPLES;countdown<=COUNTDOWN_SAMPLES!=0;
            consumed_bits<=0;consumed_snapshot<=0;window_head<=0;generation<=generation+1'b1;
            pending<=0;scan_plucks<=0;launch<=0;found<=0;next_found<=0;
            miss_add<=0;miss_event<=0;snapshot_valid<=1;finished<=0;deadline_miss<=0;
            score<=0;combo<=0;max_combo<=0;hits<=0;misses<=0;wrongs<=0;judgement<=0;judgement_epoch<=0;
            fault<=!catalog_valid || catalog_count==0 || catalog_count>2048 ||
                {1'b0,catalog_base}+catalog_count>2048 || catalog_duration==0 || catalog_duration>28800000;
            fault_code<=!catalog_valid ? 4'd1 : catalog_count==0 || catalog_count>2048 ||
                {1'b0,catalog_base}+catalog_count>2048 ? 4'd2 :
                catalog_duration==0 || catalog_duration>28800000 ? 4'd3 : 4'd0;
            for(i=0;i<4;i=i+1)end_time[i]<=0;
        end else if(!enable || fault)begin
            state<=IDLE;pending<=0;launch<=0;miss_event<=0;snapshot_valid<=0;
        end else begin
            miss_event<=0;snapshot_valid<=0;
            for(i=0;i<4;i=i+1)if(pluck_valid[i] && !countdown && !finished)begin
                pending[i]<=1;pending_velocity[i*2+:2]<=velocity[i*2+:2];pluck_times[i*32+:32]<=elapsed;
            end
            if(sample_tick)begin
                launch<=0;
                for(i=0;i<4;i=i+1)if(note_off[i])end_time[i]<=0;
                if(countdown)begin
                    if(countdown_left<=1)begin countdown<=0;countdown_left<=0;end
                    else countdown_left<=countdown_left-1'b1;
                end else if(!finished)begin
                    elapsed<=elapsed+1'b1;
                    if({1'b0,elapsed}>={1'b0,duration_limit}+WINDOW_SAMPLES)finished<=1;
                    if(state!=IDLE)begin deadline_miss<=1;fault<=1;fault_code<=6;end
                    else begin
                        scan_plucks<=pending|pluck_valid;scan_velocity<=pending_velocity;scan_times<=pluck_times;
                        for(i=0;i<4;i=i+1)begin
                            if(pluck_valid[i])begin scan_velocity[i*2+:2]<=velocity[i*2+:2];scan_times[i*32+:32]<=elapsed;end
                            best_error[i]<=14'h3fff;
                        end
                        pending<=0;found<=0;next_found<=0;miss_add<=0;
                        scan_begin<=window_head;scan_id<=window_head;retire_head<=window_head;retire_open<=1;
                        scan_end<=count-window_head>65 ? window_head+12'd65 : count;
                        state<=window_head<count ? READ : COMMIT;
                    end
                end
            end
            case(state)
                READ:state<=EVALUATE;
                EVALUATE:begin
                    previous_onset<=onset;
                    if(invalid_word || (probe && {1'b0,onset}<={1'b0,elapsed}+DISPLAY_AHEAD_SAMPLES))begin
                        fault<=1;fault_code<=invalid_word ? 4'd4 : 4'd5;state<=IDLE;launch<=0;
                    end else begin
                        if(!probe)begin
                            if(!consumed_bits[scan_id[5:0]])begin
                                if(demo && onset<=elapsed)begin
                                    found[lane]<=1;best_slot[lane]<=scan_id[5:0];best_phase[lane]<=midi_phase(midi);best_duration[lane]<=duration;
                                end else if(!demo && eligible && absolute_error<best_error[lane])begin
                                    found[lane]<=1;best_error[lane]<=absolute_error[13:0];best_slot[lane]<=scan_id[5:0];
                                    best_phase[lane]<=midi_phase(midi);best_duration[lane]<=duration;
                                end
                                if(expired)begin
                                    consumed_bits[scan_id[5:0]]<=1;miss_add<=miss_add+1'b1;
                                    judgement[lane*3+:3]<=4;judgement_epoch[lane*2+:2]<=judgement_epoch[lane*2+:2]+1'b1;
                                end
                                if(!next_found[lane] && onset>=elapsed && {1'b0,onset}<={1'b0,elapsed}+48000)begin
                                    next_found[lane]<=1;next_phase[lane]<=midi_phase(midi);next_duration[lane]<=duration;
                                end
                            end
                            // A slot is cleared only when its old global event retires.
                            // The next 64-event window can then reuse it without stale hits.
                            if(retire_open && (consumed_bits[scan_id[5:0]] || expired))begin
                                retire_head<=scan_id+1'b1;consumed_bits[scan_id[5:0]]<=0;
                            end else retire_open<=0;
                        end
                        if(scan_id+1'b1==scan_end)state<=COMMIT;
                        else begin scan_id<=scan_id+1'b1;state<=READ;end
                    end
                end
                COMMIT:begin
                    commit_bits=consumed_bits;score_add=0;hit_add=0;wrong_add=0;
                    combo_next=miss_add!=0 ? 16'd0 : combo;max_next=max_combo;launch_next=0;
                    for(i=0;i<4;i=i+1)begin
                        if(found[i])begin
                            commit_bits[best_slot[i]]=1;target_phase[i*32+:32]<={6'd0,best_phase[i]};
                            end_time[i]<=elapsed+best_duration[i];launch_next[i]=1;
                            note_velocity[i*2+:2]<=demo ? 2'd2 : scan_velocity[i*2+:2];
                            if(!demo)begin
                                judgement_epoch[i*2+:2]<=judgement_epoch[i*2+:2]+1'b1;hit_add=hit_add+1'b1;
                                if(best_error[i]<=PERFECT_SAMPLES)begin score_add=score_add+100;combo_next=add16(combo_next,7'd1);judgement[i*3+:3]<=1;end
                                else if(best_error[i]<=GOOD_SAMPLES)begin score_add=score_add+70;combo_next=add16(combo_next,7'd1);judgement[i*3+:3]<=2;end
                                else begin score_add=score_add+25;combo_next=0;judgement[i*3+:3]<=3;end
                                if(combo_next>max_next)max_next=combo_next;
                            end
                        end else if(scan_plucks[i] && !demo)begin
                            judgement_epoch[i*2+:2]<=judgement_epoch[i*2+:2]+1'b1;
                            wrong_add=wrong_add+1'b1;combo_next=0;judgement[i*3+:3]<=5;launch_next[i]=1;
                            note_velocity[i*2+:2]<=scan_velocity[i*2+:2];end_time[i]<=elapsed+(next_found[i] ? next_duration[i] : 32'd14400);
                            target_phase[i*32+:32]<=next_found[i] ? {6'd0,next_phase[i]} :
                                i==0 ? 32'h01c20d2f : i==1 ? 32'h0151285d : i==2 ? 32'h010b9a2b : 32'h00c879a3;
                        end
                    end
                    consumed_bits<=commit_bits;consumed_snapshot<=commit_bits;window_head<=retire_head;
                    launch<=launch_next;score_next={1'b0,score}+score_add;score<=score_next[32] ? 32'hffffffff : score_next[31:0];
                    hits<=add16(hits,hit_add);misses<=add16(misses,miss_add);wrongs<=add16(wrongs,wrong_add);
                    combo<=combo_next;max_combo<=max_next;miss_event<=miss_add!=0 && !demo;snapshot_valid<=1;state<=IDLE;
                end
            endcase
        end
    end
endmodule
