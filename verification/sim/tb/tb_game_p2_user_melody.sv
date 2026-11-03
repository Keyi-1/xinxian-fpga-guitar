`timescale 1ns/1ps
// Complete user score at exactly 12 samples/quarter for accelerated control
// checking. 1/4 and 1/3 beats remain exact. Audio sample rate is not changed.
module tb_game_p2_user_melody;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,tick=0,start=0,demo=1;
    reg [3:0] pluck=0;
    reg [11:0] count=212;
    reg [31:0] limit=1824;
    reg [95:0] original[0:2047],memory[0:2047],data=0;
    wire read;wire [10:0] address;
    wire [3:0] on,off,code;
    wire [127:0] phase;wire [7:0] velocity;
    wire [31:0] now,score;wire [15:0] hits,misses,wrongs,combo,max_combo;
    wire [11:0] head;wire finished,fault,deadline;
    integer index=0,stage=0,launches=0,high=0,busy=0,max_busy=0,reads=0,max_reads=0,i;
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(0),.PERFECT_SAMPLES(1),
        .GOOD_SAMPLES(1),.WINDOW_SAMPLES(2),.DISPLAY_AHEAD_SAMPLES(26)) dut(
        .clk(clk),.rst_n(rst),.sample_tick(tick),.enable(1'b1),.start_song(start),.demo(demo),
        .catalog_valid(1'b1),.catalog_base(11'd491),.catalog_count(count),.catalog_duration(limit),
        .pluck_valid(pluck),.velocity(8'haa),.read_enable(read),.read_address(address),.read_data(data),
        .note_on(on),.note_off(off),.target_phase(phase),.note_velocity(velocity),.song_time(now),
        .countdown(),.finished(finished),.fault(fault),.deadline_miss(deadline),.fault_code(code),
        .miss_event(),.snapshot_valid(),.score(score),.combo(combo),.max_combo(max_combo),
        .hits(hits),.misses(misses),.wrongs(wrongs),.judgement(),.judgement_epoch(),
        .window_head(head),.window_count(),.consumed_snapshot(),.generation());
    always @(posedge clk)if(read)data<=memory[address];
    function automatic [31:0] expected_phase(input integer midi);
        real hz;
        begin hz=440.0*(2.0**((midi-69)/12.0));expected_phase=$rtoi(hz*4294967296.0/48000.0+0.5);end
    endfunction
    integer lane,midi,expected_time;
    always @(posedge clk)if(rst)begin
        if(dut.state!=0)begin busy=busy+1;if(busy>max_busy)max_busy=busy;end else busy=0;
        if(read)reads=reads+1;
        if(tick)begin
            if(reads>max_reads)max_reads=reads;reads=0;
            if(fault || deadline)$fatal(1,"FAIL: melody fault code=%0d t=%0d",code,now);
            if(on!=0)begin
                if(index>=count || $countones(on)!=1)$fatal(1,"FAIL: duplicate/extra melody launch");
                lane=memory[491+index][72:71];midi=memory[491+index][70:64];
                expected_time=memory[491+index][31:0]+(demo ? 0 : 1);
                if(demo && expected_time==0)expected_time=1;
                if(on!==(4'b1<<lane) || phase[lane*32+:32]!==expected_phase(midi) ||
                   velocity[lane*2+:2]!==2 || now!=expected_time)
                    $fatal(1,"FAIL: melody launch n=%0d t=%0d expected=%0d MIDI=%0d phase=%h expectedphase=%h",index,now,expected_time,midi,phase[lane*32+:32],expected_phase(midi));
                if(midi==79)begin
                    if(!phase[lane*32+26])$fatal(1,"FAIL: G5 phase bit26 truncated");
                    high=high+1;
                end
                index=index+1;launches=launches+1;
            end
        end
    end
    task restart;
        @(negedge clk);start=1;index=0;launches=0;high=0;
        @(negedge clk);start=0;
    endtask
    task step(input [3:0] strike);
        @(negedge clk);tick=1;pluck=strike;
        @(negedge clk);tick=0;pluck=0;repeat(254)@(negedge clk);
    endtask
    integer next_strike;
    initial begin
        $readmemh("../../mem/game_p2_static.mem",original);
        for(i=0;i<2048;i=i+1)memory[i]=original[i];
        for(i=0;i<212;i=i+1)begin
            if(original[491+i][31:0]%4000 || original[491+i][63:32]%4000)
                $fatal(1,"FAIL: compression must preserve every fraction exactly");
            memory[491+i][31:0]=original[491+i][31:0]/4000;
            memory[491+i][63:32]=original[491+i][63:32]/4000;
        end
        repeat(5)@(negedge clk);rst=1;restart();
        while(!finished)step(0);
        if(launches!=212 || high!=1 || head!=212 || hits || misses || score)$fatal(1,"FAIL: complete 38-bar preview");
        $display("PASS: all 212 melody launches/27-bit phases, 38 bars, 30 merged ties, 13 rests and G5 preview; exact 4000x control acceleration");
        demo=0;stage=1;restart();next_strike=0;
        while(!finished)begin
            if(next_strike<count && now==memory[491+next_strike][31:0])begin
                step(4'b1<<memory[491+next_strike][72:71]);next_strike=next_strike+1;
            end else step(0);
        end
        if(hits!=212 || score!=21200 || misses || wrongs || max_combo!=212 || launches!=212 || high!=1)
            $fatal(1,"FAIL: complete melody Perfect scoring hits=%0d score=%0d misses=%0d wrongs=%0d",hits,score,misses,wrongs);
        restart();while(!finished)step(0);
        if(misses!=212 || hits || wrongs || launches || head!=212)$fatal(1,"FAIL: complete melody silent Miss/retirement");
        // Every extended MIDI code, including all newly accepted 73..79.
        count=30;limit=300;
        for(i=0;i<30;i=i+1)memory[491+i]=96'(10+i*8)|(96'd4<<32)|(96'(50+i)<<64)|(96'(i%4)<<71);
        demo=1;restart();while(!finished)step(0);
        if(launches!=30 || high!=1 || max_busy>132 || max_reads>65)$fatal(1,"FAIL: D3-G5/deadline coverage");
        $display("PASS: complete melody play/preview/Miss/restart, 212 Perfect hits, all MIDI50..79 exact DDS; <=%0d reads/%0d busy clocks per256",max_reads,max_busy);
        $finish;
    end
    initial begin #30000000;$fatal(1,"FAIL: complete melody controller timeout");end
endmodule
