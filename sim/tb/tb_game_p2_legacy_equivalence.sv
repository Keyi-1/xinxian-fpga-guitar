`timescale 1ns/1ps
// Sample-boundary comparison to frozen P1. Jasmine's event timing is compressed
// identically in both memories for simulation; Python separately proves the
// shipped static data preserves every original sample timestamp and DDS value.
module tb_game_p2_legacy_equivalence;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,demo=1;
    reg [7:0] divider=0;
    always @(posedge clk)divider<=!rst_n ? 0 : divider+1'b1;
    wire tick=divider==255;
    reg [3:0] pluck=0;
    wire [3:0] p1_on,p1_off,p2_on,p2_off;
    wire [127:0] p1_phase,p2_phase,p1_consumed;
    wire [7:0] p1_velocity,p2_velocity,p1_combo,p1_max,p1_hits,p1_misses,p1_wrongs,p1_epoch,p2_epoch;
    wire [15:0] p2_combo,p2_max,p2_hits,p2_misses,p2_wrongs;
    wire [19:0] p1_score;
    wire [31:0] p2_score,p1_time,p2_time;
    wire [11:0] p1_judgement,p2_judgement,head;
    wire p1_finished,p2_finished,p1_deadline,p2_deadline,fault;
    wire [63:0] p2_consumed;
    wire rd;wire [10:0] address;
    reg [95:0] memory[0:2047],data;
    always @(posedge clk)if(rd)data<=memory[address];
    game_note_controller_p1 #(.EVENT_COUNT(67),.DURATION_SAMPLES(4000),.COUNTDOWN_SAMPLES(0),
        .PERFECT_SAMPLES(1),.GOOD_SAMPLES(2),.WINDOW_SAMPLES(3)) reference(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(1'b1),.start_song(start),.demo(demo),
        .pluck_valid(pluck),.velocity(8'he4),.note_on(p1_on),.note_off(p1_off),.target_phase(p1_phase),
        .note_velocity(p1_velocity),.song_time(p1_time),.countdown(),.finished(p1_finished),
        .score(p1_score),.combo(p1_combo),.max_combo(p1_max),.hits(p1_hits),.misses(p1_misses),.wrongs(p1_wrongs),
        .judgement(p1_judgement),.consumed(p1_consumed),.judgement_epoch(p1_epoch),.deadline_miss(p1_deadline),.miss_event());
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(0),.PERFECT_SAMPLES(1),.GOOD_SAMPLES(2),
        .WINDOW_SAMPLES(3),.DISPLAY_AHEAD_SAMPLES(5)) candidate(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(1'b1),.start_song(start),.demo(demo),
        .catalog_valid(1'b1),.catalog_base(11'd0),.catalog_count(12'd67),.catalog_duration(32'd4000),
        .pluck_valid(pluck),.velocity(8'he4),.read_enable(rd),.read_address(address),.read_data(data),
        .note_on(p2_on),.note_off(p2_off),.target_phase(p2_phase),.note_velocity(p2_velocity),
        .song_time(p2_time),.countdown(),.finished(p2_finished),.fault(fault),.fault_code(),.deadline_miss(p2_deadline),
        .score(p2_score),.combo(p2_combo),.max_combo(p2_max),.hits(p2_hits),.misses(p2_misses),.wrongs(p2_wrongs),
        .judgement(p2_judgement),.judgement_epoch(p2_epoch),.window_head(head),.window_count(),
        .consumed_snapshot(p2_consumed),.generation(),.miss_event(),.snapshot_valid());
    integer samples=0,trial=0,i,t,d,midi,matched,launches=0;
    reg [79:0] old;
    reg [25:0] tuning[50:72];
    function automatic [25:0] midi_phase(input [6:0] midi);
        `include "../config/game_p2_phase.vh"
    endfunction
    always @(posedge clk)if(rst_n && tick && !start)begin
        samples=samples+1;launches=launches+$countones(p2_on);
        if({p1_on,p1_off,p1_phase,p1_velocity,p1_time,p1_finished,p1_score,p1_combo,p1_max,p1_hits,p1_misses,p1_wrongs,p1_judgement,p1_epoch} !==
           {p2_on,p2_off,p2_phase,p2_velocity,p2_time,p2_finished,p2_score[19:0],p2_combo[7:0],p2_max[7:0],p2_hits[7:0],p2_misses[7:0],p2_wrongs[7:0],p2_judgement,p2_epoch})
            $fatal(1,"FAIL: P1/P2 sample mismatch trial=%0d t=%0d on=%b/%b off=%b/%b score=%0d/%0d hits=%0d/%0d miss=%0d/%0d wrong=%0d/%0d",trial,p1_time,p1_on,p2_on,p1_off,p2_off,p1_score,p2_score,p1_hits,p2_hits,p1_misses,p2_misses,p1_wrongs,p2_wrongs);
        if(fault || p1_deadline || p2_deadline)$fatal(1,"FAIL: sample deadline or data fault");
        for(i=0;i<67;i=i+1)if(i>=head && i<head+64 && p1_consumed[i]!==p2_consumed[i%64])
            $fatal(1,"FAIL: active consumption mismatch event=%0d head=%0d",i,head);
    end
    initial begin
        #1;
        for(midi=50;midi<=72;midi=midi+1)tuning[midi]=midi_phase(midi);
        for(i=0;i<2048;i=i+1)memory[i]=0;
        for(i=0;i<67;i=i+1)begin
            old=reference.u_rom.memory[i];t=old[23:0]/480;d=old[47:24]/480;matched=0;
            for(midi=50;midi<=72;midi=midi+1)if(tuning[midi]==old[73:48])matched=midi;
            if(matched==0 || d==0)$fatal(1,"FAIL: frozen Jasmine conversion fixture");
            reference.u_rom.memory[i]=(80'(old[75:74])<<74)|(80'(old[73:48])<<48)|(80'(d)<<24)|80'(t);
            memory[i]=96'(t)|(96'(d)<<32)|(96'(matched)<<64)|(96'(old[75:74])<<71)|(96'd2<<73);
        end
        repeat(5)@(negedge clk);rst_n=1;
        for(trial=0;trial<3;trial=trial+1)begin
            @(negedge clk);start=1;demo=trial==0;launches=0;
            @(negedge clk);start=0;
            while(!p1_finished)begin
                @(negedge clk);pluck=trial==1 && (p1_time%17==0) ? 4'b1111 : 4'd0;
            end
            @(negedge clk);pluck=0;
            repeat(300)@(negedge clk);
            if(trial==0 && launches!=67)$fatal(1,"FAIL: preview missed Jasmine events");
            if(trial==2 && p2_misses!=67)$fatal(1,"FAIL: silent game lost misses");
        end
        $display("PASS: frozen P1/P2 Jasmine sample-boundary equivalence: %0d samples; complete preview, actual plucks/Wrong/judgement/velocity/release, silent Miss and restart",samples);
        $finish;
    end
    initial begin #40000000;$fatal(1,"FAIL: P1/P2 comparison timeout");end
endmodule
