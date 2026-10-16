`timescale 1ns/1ps
// Compare every public output on every clock, including scan/commit cycles.
// Only elapsed/statistic preloads are test acceleration; both instances receive
// identical preloads. The immutable reference is the previously verified A4.
module tb_game_p2_window_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,enable=1,start_song=0,demo=0,catalog_valid=1;
    reg [10:0] base=0;
    reg [11:0] count=2048;
    reg [31:0] duration_limit=28800000;
    reg [3:0] pluck=0;
    reg [7:0] velocity=0;
    reg [95:0] memory[0:2047],data=0;
    typedef struct packed {
        logic rd;logic [10:0] address;logic [3:0] on,off;
        logic [127:0] phase;logic [7:0] velocity;logic [31:0] time_now;
        logic countdown,finished,fault,deadline;logic [3:0] code;
        logic miss_event,snapshot;logic [31:0] score;
        logic [15:0] combo,max_combo,hits,misses,wrongs;
        logic [11:0] judgement;logic [7:0] epoch;
        logic [11:0] head;logic [6:0] window_count;logic [63:0] consumed;
        logic [15:0] generation;
    } outputs_t;
    wire outputs_t a,b;
`define INPUTS .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(enable), \
    .start_song(start_song),.demo(demo),.catalog_valid(catalog_valid), \
    .catalog_base(base),.catalog_count(count),.catalog_duration(duration_limit), \
    .pluck_valid(pluck),.velocity(velocity),.read_data(data)
`define OUTPUTS(x) .read_enable(x.rd),.read_address(x.address),.note_on(x.on), \
    .note_off(x.off),.target_phase(x.phase),.note_velocity(x.velocity), \
    .song_time(x.time_now),.countdown(x.countdown),.finished(x.finished), \
    .fault(x.fault),.deadline_miss(x.deadline),.fault_code(x.code), \
    .miss_event(x.miss_event),.snapshot_valid(x.snapshot),.score(x.score), \
    .combo(x.combo),.max_combo(x.max_combo),.hits(x.hits),.misses(x.misses), \
    .wrongs(x.wrongs),.judgement(x.judgement),.judgement_epoch(x.epoch), \
    .window_head(x.head),.window_count(x.window_count), \
    .consumed_snapshot(x.consumed),.generation(x.generation)
    game_p2_window_controller #(.COUNTDOWN_SAMPLES(8)) dut(`INPUTS,`OUTPUTS(a));
    game_p2_window_controller_a4 #(.COUNTDOWN_SAMPLES(8)) ref_a4(`INPUTS,`OUTPUTS(b));
`undef INPUTS
`undef OUTPUTS
    always @(posedge clk)if(a.rd)data<=memory[a.address];
    integer clocks=0,snapshots=0,launches=0,faults=0,seed=32'h57ab192e;
    integer max_busy=0,busy=0;
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            clocks=clocks+1;
            if(a!==b)$fatal(1,"FAIL: A4 output mismatch clock=%0d time=%0d state=%0d a=%h b=%h",clocks,b.time_now,ref_a4.state,a,b);
            if(a.snapshot)snapshots=snapshots+1;
            if(a.on)launches=launches+1;
            if(a.fault)faults=faults+1;
            if(dut.state!=0)begin busy=busy+1;if(busy>max_busy)max_busy=busy;end else busy=0;
        end
    end
    function automatic [95:0] word(input integer t,d,l,m);
        word=96'(t)|(96'(d)<<32)|(96'(m)<<64)|(96'(l)<<71)|(96'd2<<73);
    endfunction
    task automatic restart;
        @(negedge clk);start_song=1;@(negedge clk);start_song=0;
        repeat(8)step(0,0);
    endtask
    task automatic jump(input reg [31:0] t);
        @(negedge clk);dut.elapsed=t;ref_a4.elapsed=t;
    endtask
    task automatic step(input reg [3:0] mask,input bit dynamic_pluck);
        @(negedge clk);tick=1;pluck=mask;velocity=$urandom;
        @(negedge clk);tick=0;pluck=0;
        repeat(254)begin
            @(negedge clk);
            pluck=dynamic_pluck && ($urandom_range(0,31)==0) ? $urandom : 0;
            velocity=$urandom;
        end
        pluck=0;
    endtask
    integer i,j,k,t,offset,l;
    reg [63:0] bits_before;
    initial begin
        seed=$urandom(seed);
        for(i=0;i<2048;i=i+1)memory[i]=word(i*12000+24000,6000,i%4,50+i%23);
        repeat(5)@(negedge clk);rst_n=1;
        // Full bank, all 32 circular-mask wraps, dynamic input during scans.
        demo=1;restart();
        for(i=0;i<2048;i=i+1)begin jump(i*12000+24000);step(0,i%29==0);end
        if(a.fault || a.head<2040)$fatal(1,"FAIL: full bank preview coverage");
        // Exact +/- judgement boundaries, simultaneous lanes and wrong notes.
        demo=0;count=32;restart();
        for(i=0;i<32;i=i+1)begin
            offset=i%7==0 ? -7201 : i%7==1 ? -7200 : i%7==2 ? -4320 :
                i%7==3 ? -1680 : i%7==4 ? 0 : i%7==5 ? 4320 : 7200;
            jump(i*12000+24000+offset);step(4'b1<<(i%4),1);
            step(15,0);
        end
        // Exhaustive found-lane masks, randomized equal/different ring slots,
        // saturating counters/score and lane-order-dependent combo reset.
        count=1;restart();
        for(i=0;i<512;i=i+1)begin
            @(negedge clk);
            dut.state=3;ref_a4.state=3;
            dut.found=i%16;ref_a4.found=i%16;
            dut.scan_plucks=i/16;ref_a4.scan_plucks=i/16;
            dut.miss_add=i%65;ref_a4.miss_add=i%65;
            dut.consumed_bits={$urandom,$urandom};ref_a4.consumed_bits=dut.consumed_bits;
            dut.score=32'hffffff00+i%256;ref_a4.score=dut.score;
            dut.combo=16'hfffe;ref_a4.combo=16'hfffe;
            dut.max_combo=16'hfffe;ref_a4.max_combo=16'hfffe;
            dut.hits=16'hfffd;ref_a4.hits=16'hfffd;
            dut.misses=16'hfffd;ref_a4.misses=16'hfffd;
            dut.wrongs=16'hfffd;ref_a4.wrongs=16'hfffd;
            for(j=0;j<4;j=j+1)begin
                dut.best_slot[j]=$urandom;ref_a4.best_slot[j]=dut.best_slot[j];
                dut.best_error[j]=(i+j)%3==0 ? 1680 : (i+j)%3==1 ? 4320 : 7200;
                ref_a4.best_error[j]=dut.best_error[j];
                dut.best_duration[j]=$urandom_range(1,28800000);ref_a4.best_duration[j]=dut.best_duration[j];
                dut.next_duration[j]=28800000;ref_a4.next_duration[j]=28800000;
            end
            repeat(2)@(negedge clk);
        end
        // Ten-minute bound, 2^24 crossing, maximum valid duration, end-time
        // addition wider than 25 bits, finished tail, restart/disable midscan.
        count=2;memory[0]=word(0,28800000,0,64);memory[1]=word(28799990,10,1,59);
        restart();jump(16777215);step(15,1);jump(28799989);step(15,1);
        jump(28807200);step(0,0);step(0,0);
        if(!a.finished || a.fault)$fatal(1,"FAIL: ten-minute bound");
        for(i=0;i<50;i=i+1)begin
            restart();@(negedge clk);tick=1;@(negedge clk);tick=0;
            repeat(i%5)@(negedge clk);enable=0;
            repeat(3)@(negedge clk);enable=1;
        end
        // Invalid high bits must be validated at 32 bits, never truncated into
        // an apparently valid event or catalogue duration.
        count=1;
        for(i=0;i<32;i=i+1)begin
            duration_limit=i%2 ? 32'hffffffff : 28800001;restart();step(15,0);
            if(!a.fault || a.code!=3)$fatal(1,"FAIL: invalid catalogue accepted");
        end
        duration_limit=28800000;
        for(i=0;i<32;i=i+1)begin
            memory[0]=i%2 ? word(0,32'h80000001,0,64) : word(32'h80000000,1,0,64);
            restart();step(15,0);
            if(!a.fault || a.code!=4)$fatal(1,"FAIL: invalid record accepted");
        end
        // Metadata bounds, zero duration, invalid MIDI, reserved bits, sorted
        // onset, dense 65-event guard and too-early sample deadline.
        memory[0]=word(10,1,0,64);catalog_valid=0;restart();catalog_valid=1;
        base=2047;count=2;restart();base=0;count=1;
        memory[0]=word(10,0,0,64);restart();step(0,0);
        memory[0]=word(10,1,0,127);restart();step(0,0);
        memory[0]=word(10,1,0,64)|(96'd1<<75);restart();step(0,0);
        count=2;memory[0]=word(10,1,0,64);memory[1]=word(9,1,1,59);restart();step(0,0);
        count=65;for(i=0;i<65;i=i+1)memory[i]=word(100,1,i%4,64);
        restart();step(0,0);
        count=1;memory[0]=word(10,1,0,64);restart();
        @(negedge clk);tick=1;@(negedge clk);tick=0;@(negedge clk);tick=1;
        @(negedge clk);tick=0;repeat(8)@(negedge clk);
        if(!a.deadline || !a.fault)$fatal(1,"FAIL: deadline fault coverage");
        if(max_busy>132)$fatal(1,"FAIL: scan deadline increased");
        $display("PASS: A4 cycle-exact controller equivalence %0d clocks, %0d snapshots, 2048 events/32 wraps, dynamic plucks, 512 commits, saturation, 10-minute bounds, invalid high bits, switching/faults; max busy %0d",clocks,snapshots,max_busy);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: controller equivalence timeout");end
endmodule
