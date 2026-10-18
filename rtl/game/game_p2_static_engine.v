// Immutable score bank shared by the production P2 audio and display paths.
// Timbre is metadata only here; use it after the router's release/ack handshake.
module game_p2_static_engine #(parameter integer COUNTDOWN_SAMPLES=96000,WRITABLE=0)
  (input wire clk,rst_n,sample_tick,enable,start_song,demo,
   input wire [2:0] selected_slot,input wire allow_test_slot,
   input wire [3:0] pluck_valid,input wire [7:0] velocity,
   input wire display_clk,display_read,input wire [10:0] display_address,
   output wire [95:0] display_data,
   input wire [4:0] overlay_valid,input wire [479:0] overlay_data,
   input wire write_enable,input wire [10:0] write_address,input wire [95:0] write_data,
   output reg [2:0] active_slot,output reg [1:0] recommended_timbre,
   output reg [10:0] active_base,output reg [11:0] active_count,
   output reg [31:0] active_duration,
   output wire [3:0] note_on,note_off,output wire [127:0] target_phase,
   output wire [7:0] note_velocity,output wire [31:0] song_time,score,
   output wire [15:0] combo,max_combo,hits,misses,wrongs,
   output wire [11:0] judgement,window_head,output wire [6:0] window_count,
   output wire [7:0] judgement_epoch,output wire [63:0] consumed_snapshot,
   output wire [15:0] generation,output wire countdown,finished,fault,deadline_miss,
   output wire [3:0] fault_code,output wire miss_event,snapshot_valid);
    wire valid,playable,test_only;
    wire [10:0] base,address;
    wire [11:0] count;
    wire [31:0] duration;
    wire [1:0] timbre;
    wire read_enable;
    wire [95:0] data;
    generate if(WRITABLE)begin:runtime_bank
    game_p3_catalog catalog(.slot(selected_slot),.overlay_valid(overlay_valid),.overlay_data(overlay_data),
        .valid(valid),.playable(playable),.test_only(test_only),.progress_step(),
        .base(base),.event_count(count),.duration(duration),.timbre(timbre));
    game_p3_score_bank bank(.audio_clk(clk),.audio_read(read_enable),.audio_address(address),.audio_data(data),
        .display_clk(display_clk),.display_read(display_read),.display_address(display_address),.display_data(display_data),
        .write_enable(write_enable),.write_address(write_address),.write_data(write_data));
    end else begin:static_bank
    game_p2_catalog catalog(.slot(selected_slot),.valid(valid),.playable(playable),.test_only(test_only),
        .base(base),.event_count(count),.duration(duration),.timbre(timbre));
    game_p2_score_bank bank(.audio_clk(clk),.audio_read(read_enable),.audio_address(address),.audio_data(data),
        .display_clk(display_clk),.display_read(display_read),.display_address(display_address),.display_data(display_data));
    end endgenerate
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(COUNTDOWN_SAMPLES)) controller(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.enable(enable),.start_song(start_song),.demo(demo),
        .catalog_valid(valid && (playable || (test_only && allow_test_slot))),
        .catalog_base(base),.catalog_count(count),.catalog_duration(duration),
        .pluck_valid(pluck_valid),.velocity(velocity),.read_enable(read_enable),.read_address(address),.read_data(data),
        .note_on(note_on),.note_off(note_off),.target_phase(target_phase),.note_velocity(note_velocity),
        .song_time(song_time),.countdown(countdown),.finished(finished),.fault(fault),.fault_code(fault_code),.deadline_miss(deadline_miss),
        .score(score),.combo(combo),.max_combo(max_combo),.hits(hits),.misses(misses),.wrongs(wrongs),
        .judgement(judgement),.judgement_epoch(judgement_epoch),.miss_event(miss_event),.snapshot_valid(snapshot_valid),
        .window_head(window_head),.window_count(window_count),.consumed_snapshot(consumed_snapshot),.generation(generation));
    always @(posedge clk)begin
        if(!rst_n)begin active_slot<=0;recommended_timbre<=0;active_base<=0;active_count<=0;active_duration<=0;end
        else if(start_song)begin active_slot<=selected_slot;recommended_timbre<=timbre;
            active_base<=base;active_count<=count;active_duration<=duration;end
    end
endmodule
