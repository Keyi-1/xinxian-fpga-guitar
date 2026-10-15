`timescale 1ns/1ps
module tb_game_p2_window;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,enable=1,start_song=0,demo=1,catalog_valid=1;
    reg [10:0] base=0;
    reg [11:0] count=2048;
    reg [31:0] duration_limit=20000;
    reg [3:0] pluck=0;
    reg [95:0] memory[0:2047],data=0;
    wire rd;wire [10:0] address;
    always @(posedge clk)if(rd)data<=memory[address];
    wire [3:0] note_on,note_off,fault_code;
    wire [31:0] time_now,score;
    wire [15:0] hits,misses,wrongs,combo,max_combo,generation;
    wire [11:0] head;
    wire [6:0] window_count;
    wire [63:0] consumed;
    wire countdown,finished,fault,deadline,snapshot_valid;
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(0),.PERFECT_SAMPLES(1),
        .GOOD_SAMPLES(2),.WINDOW_SAMPLES(3),.DISPLAY_AHEAD_SAMPLES(100)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable),.start_song(start_song),.demo(demo),
        .catalog_valid(catalog_valid),.catalog_base(base),.catalog_count(count),.catalog_duration(duration_limit),
        .pluck_valid(pluck),.velocity(8'he4),.read_enable(rd),.read_address(address),.read_data(data),
        .note_on(note_on),.note_off(note_off),.target_phase(),.note_velocity(),.song_time(time_now),
        .countdown(countdown),.finished(finished),.fault(fault),.fault_code(fault_code),.deadline_miss(deadline),
        .score(score),.hits(hits),.misses(misses),.wrongs(wrongs),.combo(combo),.max_combo(max_combo),
        .judgement(),.judgement_epoch(),.window_head(head),.window_count(window_count),
        .consumed_snapshot(consumed),.generation(generation),.miss_event(),.snapshot_valid(snapshot_valid));
    integer i,launches=0,reads=0,max_reads=0,busy=0,max_busy=0,clocks=0;
    reg [75:0] previous_window=0;
    always @(posedge clk)begin
        if(rst_n)begin
            clocks=clocks+1;
            if(tick)begin
                launches=launches+$countones(note_on);
                if(reads>max_reads)max_reads=reads;
                reads=0;
            end
            if(rd)reads=reads+1;
            if(dut.state!=0)begin busy=busy+1;if(busy>max_busy)max_busy=busy;end else busy=0;
            if(!enable && note_on!=0)$fatal(1,"FAIL: disabled launch");
        end
        #1;
        if(rst_n && !snapshot_valid && {head,consumed}!==previous_window)
            $fatal(1,"FAIL: non-atomic window publication");
        previous_window={head,consumed};
    end
    function automatic [95:0] event_word(input integer t,d,l,m);
        event_word=96'(t)|(96'(d)<<32)|(96'(m)<<64)|(96'(l)<<71)|(96'd2<<73);
    endfunction
    task automatic start;
        @(negedge clk);start_song=1;@(negedge clk);start_song=0;
    endtask
    task automatic step(input [3:0] strike);
        @(negedge clk);tick=1;pluck=strike;
        @(negedge clk);tick=0;pluck=0;
        repeat(254)@(negedge clk);
    endtask
    task automatic check(input bit pass,input string message);
        if(!pass)$fatal(1,"FAIL: %s time=%0d head=%0d launches=%0d hits=%0d misses=%0d fault=%0d",message,time_now,head,launches,hits,misses,fault_code);
    endtask
    initial begin
        for(i=0;i<2048;i=i+1)memory[i]=event_word(i*8+10,3,i%4,i%4==0 ? 64 : i%4==1 ? 59 : i%4==2 ? 55 : 50);
        repeat(5)@(negedge clk);rst_n=1;start();
        while(time_now<16400)step(0);
        check(!fault && !deadline && launches==2048 && head==2048,"2048-event preview and 32 ring-slot wraps");
        check(score==0 && hits==0 && misses==0,"preview stays separate from scoring");
        check(max_reads<=65 && max_busy<=132,"fixed read/deadline budget");
        $display("PASS: 2048 events, 32 ring wraps, <=%0d reads / %0d busy clocks per sample",max_reads,max_busy);
        demo=0;count=300;duration_limit=2500;launches=0;start();
        while(time_now<2420)begin
            if(time_now>=10 && (time_now-10)%8==0 && (time_now-10)/8<300)
                step(4'b1<<(((time_now-10)/8)%4));
            else step(0);
        end
        check(hits==300 && score==30000 && combo==300 && max_combo==300 && misses==0 && wrongs==0,"16-bit counts beyond 255 without wrapping");
        start();while(time_now<2420)step(0);
        check(misses==300 && hits==0 && head==300,"every expired event missed exactly once and retired");
        // A fresh song starts at a nonzero bank offset; old circular state is gone.
        base=100;count=2;duration_limit=100;
        memory[100]=event_word(10,3,0,64);memory[101]=event_word(20,3,1,59);
        demo=1;launches=0;start();while(time_now<30)step(0);
        check(launches==2 && !fault && head==2,"catalog base, restart generation and stale-slot rejection");
        enable=0;step(15);check(note_on==0,"exit gates scheduled notes");enable=1;
        // Cross 2^24 explicitly; testbench time jumps are not production inputs.
        base=0;count=2;duration_limit=28800000;
        memory[0]=event_word(16777216,2,0,64);memory[1]=event_word(28799990,2,1,59);
        launches=0;start();@(negedge clk);dut.elapsed=16777213;
        repeat(8)step(0);check(time_now>16777216 && launches==1 && !fault,"32-bit time beyond old 349.5-second limit");
        @(negedge clk);dut.elapsed=28799987;
        repeat(24)step(0);check(finished && launches==2 && !fault,"ten-minute end and tail window");
        catalog_valid=0;start();step(15);check(fault && fault_code==1 && note_on==0,"unavailable song rejected");catalog_valid=1;
        base=2047;count=2;start();step(0);check(fault && fault_code==2,"bank bounds checked");
        base=0;count=1;memory[0]=event_word(10,2,0,127);start();step(0);check(fault && fault_code==4,"invalid event rejected");
        count=65;for(i=0;i<65;i=i+1)memory[i]=event_word(100,2,i%4,64);
        start();step(0);check(fault && fault_code==5,"65th near-future event causes explicit density fault");
        count=1;memory[0]=event_word(10,2,0,64);start();
        @(negedge clk);tick=1;@(negedge clk);tick=0;@(negedge clk);tick=1;
        @(negedge clk);tick=0;check(deadline && fault && fault_code==6,"deadline failure explicit");
        start();step(0);check(!fault && !deadline,"restart clears fault and partial scan");
        $display("PASS: P2 scoring, catalogue bounds, atomic snapshots, restart/exit, 10-minute time, malformed/dense events and deadline faults; %0d clocks",clocks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: P2 window timeout");end
endmodule
