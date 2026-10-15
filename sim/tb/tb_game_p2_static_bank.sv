`timescale 1ns/1ps
module tb_game_p2_static_bank;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,display_clk=0;
    always #5 clk=~clk;always #7 display_clk=~display_clk;
    reg rst_n=0,tick=0,start=0,allow_test=0,display_read=0;
    reg [2:0] selected=0;
    reg [10:0] display_address=0;
    wire [95:0] display_data;
    wire [2:0] active;
    wire [1:0] timbre;
    wire fault;wire [3:0] fault_code;
    wire [11:0] count;
    wire [10:0] base;
    wire [31:0] duration;
    reg [95:0] expected[0:2047];
    reg [95:0] previous_display=0;
    integer i,reads=0;
    game_p2_static_engine #(.COUNTDOWN_SAMPLES(0)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.enable(1'b1),.start_song(start),.demo(1'b1),
        .selected_slot(selected),.allow_test_slot(allow_test),.pluck_valid(4'd0),.velocity(8'd0),
        .display_clk(display_clk),.display_read(display_read),.display_address(display_address),.display_data(display_data),
        .active_slot(active),.recommended_timbre(timbre),.active_base(base),.active_count(count),.active_duration(duration),
        .note_on(),.note_off(),.target_phase(),.note_velocity(),.song_time(),.score(),.combo(),.max_combo(),
        .hits(),.misses(),.wrongs(),.judgement(),.window_head(),.window_count(),.judgement_epoch(),.consumed_snapshot(),
        .generation(),.countdown(),.finished(),.fault(fault),.deadline_miss(),.fault_code(fault_code),.miss_event(),.snapshot_valid());
    initial $readmemh("../../mem/game_p2_static.mem",expected);
    always @(posedge display_clk)begin
        #1;
        if(display_read)begin
            if(display_data!==expected[display_address])$fatal(1,"FAIL: display synchronous bank read %0d",display_address);
            reads=reads+1;
        end else if(reads!=0 && display_data!==previous_display)$fatal(1,"FAIL: disabled display port changed");
        previous_display=display_data;
    end
    task automatic choose(input integer slot);
        @(negedge clk);selected=slot;start=1;@(negedge clk);start=0;
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;choose(1);
        if(fault || timbre!=1 || count!=256 || duration!=12288000)$fatal(1,"FAIL: slow arpeggio metadata");
        @(negedge clk);selected=2;
        repeat(5)@(negedge clk);
        if(active!=1 || timbre!=1)$fatal(1,"FAIL: selected metadata changed active song without start");
        choose(2);if(fault || timbre!=2 || count!=168)$fatal(1,"FAIL: wah riff metadata");
        // Concurrent audio scans while the other clock traverses the whole bank.
        fork
            begin
                for(i=0;i<2048;i=i+1)begin
                    @(negedge display_clk);display_read=1;display_address=i;
                end
                @(negedge display_clk);display_read=0;
            end
            begin
                repeat(11)begin
                    @(negedge clk);tick=1;@(negedge clk);tick=0;
                    repeat(254)@(negedge clk);
                end
            end
        join
        if(fault || reads!=2048)$fatal(1,"FAIL: concurrent immutable-bank access");
        choose(3);if(fault || timbre!=1 || count!=128 || duration!=6144000)$fatal(1,"FAIL: Qing Ge short intro exercise metadata");
        choose(4);if(!fault || fault_code!=1)$fatal(1,"FAIL: test-only slot exposed to game");
        allow_test=1;choose(4);if(fault || duration!=28800000)$fatal(1,"FAIL: explicit ten-minute diagnostic selection");
        choose(7);if(!fault || fault_code!=1)$fatal(1,"FAIL: out-of-catalog slot");
        choose(0);if(fault || count!=67 || base!=0)$fatal(1,"FAIL: Jasmine restart metadata");
        $display("PASS: five-slot validity/timbre, immutable start metadata, 2048 asynchronous display reads concurrent with audio, test-slot gating and invalid-slot recovery");
        $finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: P2 bank timeout");end
endmodule
