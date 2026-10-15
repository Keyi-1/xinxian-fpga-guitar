// Sample-aligned release handshake; one unchanged synthesis/effects chain.
module game_p2_mode_router #(
    parameter integer COUNTDOWN_SAMPLES=96000,ALLOW_AUTOPLAY_PREVIEW=1
)(input wire clk,rst_n,sample_tick,command_valid,input wire [1:0] command_mode,
  input wire [2:0] command_slot,
  input wire stable_valid,input wire [15:0] fret_id,
  input wire [3:0] pluck_valid,voice_active,input wire [7:0] velocity,
  input wire [127:0] audible_phase,
  input wire display_clk,display_read,input wire [10:0] display_address,
  output wire [95:0] display_data,
  output reg command_ack,output reg [1:0] mode,output reg switching,
  output reg timbre_load,output reg [1:0] timbre_code,
  output wire [3:0] note_on,note_off,force_release,
  output wire [127:0] target_phase,output wire [7:0] note_velocity,
  output reg [255:0] game_snapshot,output wire miss_event);
    reg seen,stop_sent,start_song,aborting;
    reg [1:0] requested_mode;
    reg [2:0] selected_slot;
    reg [127:0] stop_phase;
    wire [3:0] play_on,play_off,game_on,game_off;
    wire [127:0] play_phase,game_phase;
    wire [7:0] game_velocity,epoch;
    wire [31:0] song_time,score;
    wire [15:0] combo,max_combo,hits,misses,wrongs,generation;
    wire [11:0] judgement,head;
    wire [63:0] consumed;
    wire [2:0] active_slot;
    wire countdown,finished,fault,deadline;
    wire [1:0] song_timbre;
    game_p2_catalog catalog(.slot(selected_slot),.valid(),.playable(),.test_only(),.base(),.event_count(),.duration(),.timbre(song_timbre));
    guitar_play_control performance(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .stable_valid(stable_valid),.stable_fret_id(fret_id),
        .pluck_valid(pluck_valid & {4{mode==1 && !switching}}),.voice_active(voice_active),
        .smoothed_phase_inc(audible_phase),.note_on(play_on),.note_off(play_off),.target_phase_inc(play_phase));
    game_p2_static_engine #(.COUNTDOWN_SAMPLES(COUNTDOWN_SAMPLES)) engine(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.enable(mode>=2 && !switching),
        .start_song(start_song),.demo(mode==3),.selected_slot(selected_slot),.allow_test_slot(1'b0),
        .pluck_valid(pluck_valid),.velocity(velocity),.display_clk(display_clk),.display_read(display_read),
        .display_address(display_address),.display_data(display_data),.active_slot(active_slot),
        .note_on(game_on),.note_off(game_off),.target_phase(game_phase),.note_velocity(game_velocity),
        .song_time(song_time),.score(score),.combo(combo),.max_combo(max_combo),.hits(hits),.misses(misses),.wrongs(wrongs),
        .judgement(judgement),.judgement_epoch(epoch),.window_head(head),.consumed_snapshot(consumed),.generation(generation),
        .recommended_timbre(),.active_base(),.active_count(),.active_duration(),.window_count(),.fault_code(),.snapshot_valid(),
        .countdown(countdown),.finished(finished),.fault(fault),.deadline_miss(deadline),.miss_event(miss_event));
    assign note_on=switching || mode==0 ? 4'd0 : mode==1 ? play_on : game_on;
    assign force_release={4{switching && !stop_sent && sample_tick}};
    assign note_off=switching || mode<2 ? 4'd0 : game_off;
    assign target_phase=switching || mode==0 ? stop_phase : mode==1 ? play_phase : game_phase;
    assign note_velocity=mode==1 ? velocity : game_velocity;
    // 64-bit ring mask, 32-bit time/score, five 16-bit counters. Head and mask
    // are published together; immutable ROM remains safe across page changes.
    always @(posedge clk)begin
        if(!rst_n)game_snapshot<=0;
        else if(sample_tick)game_snapshot<={generation[5:0],head,active_slot,deadline,fault,switching,finished,countdown,mode,
            epoch,judgement,wrongs,misses,hits,max_combo,combo,score,song_time,consumed};
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            mode<=0;switching<=0;seen<=0;stop_sent<=0;start_song<=0;command_ack<=0;
            requested_mode<=0;selected_slot<=0;timbre_load<=0;timbre_code<=0;aborting<=0;
            stop_phase<={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
        end else begin
            command_ack<=0;start_song<=0;timbre_load<=0;
            if(!command_valid)seen<=0;
            if(command_valid && !seen && !switching)begin
                seen<=1;switching<=1;stop_sent<=0;aborting<=0;selected_slot<=command_slot;
                requested_mode<=(command_mode>=2 && command_slot>=4) ||
                    (command_mode==3 && !ALLOW_AUTOPLAY_PREVIEW) ? 2'd0 : command_mode;
                stop_phase<=audible_phase;
            end else if(mode>=2 && fault && !start_song && !switching)begin
                switching<=1;stop_sent<=0;requested_mode<=0;aborting<=1;stop_phase<=audible_phase;
            end
            if(switching && sample_tick)begin
                stop_sent<=1;
                if(stop_sent && voice_active==0)begin
                    mode<=requested_mode;switching<=0;command_ack<=!aborting;start_song<=requested_mode>=2;
                    if(requested_mode>=2)begin timbre_load<=1;timbre_code<=song_timbre;end
                end
            end
        end
    end
endmodule
