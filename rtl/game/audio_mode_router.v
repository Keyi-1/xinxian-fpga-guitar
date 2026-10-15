// Commands are acknowledged only after sample-aligned, sustain-independent
// release. The same synthesis/effects instance serves all four modes.
module audio_mode_router #(
    parameter integer COUNTDOWN_SAMPLES=96000,
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1
)(input wire clk,rst_n,sample_tick,command_valid,input wire [1:0] command_mode,
  input wire stable_valid,input wire [15:0] fret_id,
  input wire [3:0] pluck_valid,voice_active,input wire [7:0] velocity,
  input wire [127:0] audible_phase,
  output reg command_ack,output reg [1:0] mode,output reg switching,
  output wire [3:0] note_on,note_off,force_release,
  output wire [127:0] target_phase,output wire [7:0] note_velocity,
  output reg [255:0] game_snapshot,output wire miss_event);
    reg seen,stop_sent,start_song;
    reg [1:0] requested_mode;
    reg [127:0] stop_phase;
    wire [3:0] play_on,play_off,game_on,game_off;
    wire [127:0] play_phase,game_phase;
    wire [7:0] game_velocity;
    wire [31:0] song_time;
    wire countdown,finished,deadline_miss;
    wire [19:0] score;
    wire [7:0] combo,max_combo,hits,misses,wrongs;
    wire [11:0] judgement;
    wire [7:0] judgement_epoch;
    wire [127:0] consumed;
    guitar_play_control u_performance(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .stable_valid(stable_valid),.stable_fret_id(fret_id),
        .pluck_valid(pluck_valid & {4{mode==1 && !switching}}),.voice_active(voice_active),
        .smoothed_phase_inc(audible_phase),.note_on(play_on),.note_off(play_off),.target_phase_inc(play_phase));
    game_note_controller #(.COUNTDOWN_SAMPLES(COUNTDOWN_SAMPLES)) u_game(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.enable(mode>=2 && !switching),
        .start_song(start_song),.demo(mode==3),.pluck_valid(pluck_valid),.velocity(velocity),
        .note_on(game_on),.note_off(game_off),.target_phase(game_phase),.note_velocity(game_velocity),
        .song_time(song_time),.countdown(countdown),.finished(finished),.score(score),
        .combo(combo),.max_combo(max_combo),.hits(hits),.misses(misses),.wrongs(wrongs),
        .judgement(judgement),.judgement_epoch(judgement_epoch),.consumed(consumed),.deadline_miss(deadline_miss),.miss_event(miss_event));
    assign note_on=switching || mode==0 ? 4'd0 : mode==1 ? play_on : game_on;
    assign force_release={4{switching && !stop_sent && sample_tick}};
    assign note_off=switching || mode==0 || mode==1 ? 4'd0 : game_off;
    assign target_phase=switching || mode==0 ? stop_phase : mode==1 ? play_phase : game_phase;
    assign note_velocity=mode==1 ? velocity : game_velocity;
    // Fixed, documented layout; coherently transferred at display frame start.
    always @(posedge clk)begin
        if(!rst_n)game_snapshot<=0;
        // Reserved bits 245:238 mark fresh results, including repeat Perfects.
        else if(sample_tick)game_snapshot<={10'd0,judgement_epoch,deadline_miss,switching,finished,countdown,mode,
                          judgement,wrongs,misses,hits,max_combo,combo,score,song_time,consumed};
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            mode<=0;switching<=0;seen<=0;stop_sent<=0;start_song<=0;command_ack<=0;requested_mode<=0;
            stop_phase<={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
        end else begin
            command_ack<=0;start_song<=0;
            if(!command_valid)seen<=0;
            if(command_valid && !seen && !switching)begin
                seen<=1;switching<=1;stop_sent<=0;
                requested_mode<=command_mode==3 && ALLOW_AUTOPLAY_PREVIEW==0 ? 2'd0 : command_mode;
                stop_phase<=audible_phase;
            end
            if(switching && sample_tick)begin
                stop_sent<=1;
                if(stop_sent && voice_active==0)begin
                    mode<=requested_mode;switching<=0;command_ack<=1;start_song<=requested_mode>=2;
                end
            end
        end
    end
endmodule
