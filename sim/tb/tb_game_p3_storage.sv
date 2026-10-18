`timescale 1ns/1ps
module tb_game_p3_storage;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #5 clk=~clk;always #7 ac=~ac;
    reg rst=0,allowed=1,cv=0;reg [1:0] cmd=0,timbre=1;
    reg [2:0] slot=4;reg [11:0] count=1;
    reg [31:0] duration=48000,expected_crc=0;
    reg [127:0] data=0;
    wire ready,rv,locked,we,publish;wire [3:0] code;
    wire [10:0] wa;wire [95:0] wd,descriptor;
    wire [2:0] committed_slot;wire [4:0] ov;wire [479:0] od;
    wire vr;wire [10:0] va;reg corrupt_readback=0;
    reg ack=0,ar=0,dr=0;reg [10:0] aa=0,da=0;
    wire [95:0] ad,dd,ref_a,ref_d;
    reg [95:0] initial_words[0:2047],expected[0:2047];
    integer i,tests=0,writes=0,port_reads=0,j;
    game_p3_import #(.TIMEOUT_CYCLES(2000)) dut(
        .clk(clk),.rst_n(rst),.import_allowed(allowed),.cmd_valid(cv),.cmd_ready(ready),.cmd(cmd),
        .slot(slot),.event_count(count),.duration(duration),.expected_crc(expected_crc),.timbre(timbre),.record_data(data),
        .response_valid(rv),.response_code(code),.locked(locked),.write_enable(we),.write_address(wa),.write_data(wd),
        .verify_read(vr),.verify_address(va),.verify_data(dd^{95'd0,corrupt_readback}),
        .commit_valid(publish),.commit_ready(ack),.commit_slot(committed_slot),.commit_descriptor(descriptor),
        .overlay_valid(ov),.overlay_data(od));
    game_p3_score_bank bank(.audio_clk(ac),.audio_read(ar),.audio_address(aa),.audio_data(ad),
        .display_clk(clk),.display_read(dr || vr),.display_address(vr ? va : da),.display_data(dd),
        .write_enable(we),.write_address(wa),.write_data(wd));
    wire [10:0] ref_aa=aa<67 ? aa : aa<703 ? aa+11'd256 : 11'd2047;
    wire [10:0] ref_da=da<67 ? da : da<703 ? da+11'd256 : 11'd2047;
    game_p2_score_bank frozen(.audio_clk(ac),.audio_read(ar),.audio_address(ref_aa),.audio_data(ref_a),
        .display_clk(clk),.display_read(dr),.display_address(ref_da),.display_data(ref_d));
    function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] b);
        reg [31:0] v;integer k;
        begin v=prior^b;for(k=0;k<8;k=k+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
    endfunction
    function automatic [31:0] crc_record(input [31:0] prior,input [127:0] word);
        reg [31:0] v;integer k;
        begin v=prior;for(k=0;k<16;k=k+1)v=crc_byte(v,word[k*8+:8]);crc_record=v;end
    endfunction
    function automatic [127:0] event_word(input [31:0] onset,input [31:0] len,input [7:0] pitch,ln,input [15:0] group_id);
        event_word={16'd0,group_id,8'd0,8'd2,ln,pitch,len,onset};
    endfunction
    task automatic expect_response(input integer err);
        begin
            while(!rv)@(negedge clk);
            if(code!==err)$fatal(1,"FAIL: response expected %0d got %0d state %0d",err,code,dut.state);
            tests=tests+1;
        end
    endtask
    task automatic send(input [1:0] op,input integer err);
        begin
            @(negedge clk);while(!ready)@(negedge clk);
            cmd=op;cv=1;@(negedge clk);cv=0;expect_response(err);
        end
    endtask
    task automatic begin_song(input integer n,input [31:0] len,crc,input integer err);
        begin count=n;duration=len;expected_crc=crc;send(0,err);end
    endtask
    task automatic read_both(input integer address,input [95:0] word);
        begin
            @(negedge ac);aa=address;ar=1;@(posedge ac);#1;
            if(ad!==word)$fatal(1,"FAIL: audio row %0d got %h expected %h",address,ad,word);
            @(negedge ac);ar=0;
            @(negedge clk);da=address;dr=1;@(posedge clk);#1;
            if(dd!==word)$fatal(1,"FAIL: system row %0d",address);
            @(negedge clk);dr=0;
            port_reads=port_reads+2;
        end
    endtask
    always @(posedge clk)if(we)begin
        if(wa<703)$fatal(1,"FAIL: immutable prefix overwritten");
        expected[wa]=wd;writes=writes+1;
    end
    reg [127:0] one,two;
    reg [31:0] crc;
    reg [95:0] old_descriptor;
    initial begin
        $readmemh("../../mem/game_p3_initial.mem",initial_words);
        for(i=0;i<2048;i=i+1)expected[i]=initial_words[i];
        repeat(5)@(negedge clk);rst=1;
        // Exhaustive frozen initialization including page boundary and group.
        for(i=0;i<2048;i=i+1)begin
            read_both(i,expected[i]);
            if(ad!==ref_a || dd!==ref_d)$fatal(1,"FAIL: accepted bank mismatch %0d",i);
        end
        one=event_word(0,12000,79,0,16'hbeef);
        two=event_word(24000,12000,50,0,16'h1234);
        crc=crc_record(crc_record(32'hffffffff,one),two)^32'hffffffff;
        begin_song(2,48000,crc,0);
        if(!locked || ov!=0)$fatal(1,"FAIL: premature begin publication");
        data=one;send(1,0);data=two;send(1,0);
        // Delay the destination ack: directory/descriptor must remain coherent.
        fork
            begin send(2,0);end
            begin
                wait(publish);old_descriptor=descriptor;
                repeat(25)begin @(negedge clk);
                    if(!locked || ov!=0 || descriptor!==old_descriptor)$fatal(1,"FAIL: CDC payload changed before ack");end
                ack=1;@(negedge clk);ack=0;
            end
        join
        if(locked || !ov[4] || od[4*96+32+:11]!=703 || od[4*96+:32]!=100)$fatal(1,"FAIL: committed metadata/progress");
        old_descriptor=od[4*96+:96];
        begin_song(1,48000,crc_record(32'hffffffff,one)^32'hffffffff,0);data=one;send(1,0);
        corrupt_readback=1;send(2,4);corrupt_readback=0;
        if(od[4*96+:96]!==old_descriptor)$fatal(1,"FAIL: failed RAM readback was published");
        read_both(703,{16'hbeef,5'd0,2'd2,2'd0,7'd79,32'd12000,32'd0});
        read_both(704,{16'h1234,5'd0,2'd2,2'd0,7'd50,32'd12000,32'd24000});
        begin_song(1,48000,0,0);data=one;send(1,0);send(2,4);
        if(od[4*96+:96]!==old_descriptor || ov!=16)$fatal(1,"FAIL: CRC failure replaced old song");
        begin_song(2,48000,0,0);data=two;send(1,0);data=one;send(1,5);
        begin_song(2,48000,0,0);data=one;send(1,0);data=event_word(6000,1000,60,0,0);send(1,5);
        begin_song(1,48000,0,0);data=event_word(0,12000,80,0,0);send(1,6);
        begin_song(1,48000,0,0);data=event_word(32'hfffffff0,32'd32,79,0,0);send(1,6);
        begin_song(1,48000,0,0);data=one;data[127:112]=1;send(1,6);
        begin_song(1,48000,0,0);data=one;data[95:88]=1;send(1,6);
        begin_song(1,48000,0,0);data=one;data[79:72]=4;send(1,6);
        begin_song(1,48000,0,0);data=one;data[87:80]=4;send(1,6);
        begin_song(2,48000,0,0);data=one;send(1,0);send(2,3);
        begin_song(1,48000,0,0);data=one;send(1,0);send(1,3);
        begin_song(1,48000,0,0);send(3,0);send(2,9);
        allowed=0;begin_song(1,48000,0,1);allowed=1;
        begin_song(1,48000,0,0);allowed=0;@(negedge clk);expect_response(1);allowed=1;
        begin_song(1,48000,0,0);@(negedge clk);expect_response(8);
        begin_song(1344,48000,0,2); // Existing 2 rows must not be reused.
        begin_song(0,48000,0,6);timbre=3;begin_song(1,48000,0,6);timbre=1;
        begin_song(9,200000,0,0);
        for(i=0;i<8;i=i+1)begin data=event_word(i*12000,1000,60,0,0);send(1,0);end
        data=event_word(96000,1000,60,0,0);send(1,7);
        // All 32/96 bits, both pages; retained state and reset protection.
        for(i=0;i<2048;i=i+1)read_both(i,expected[i]);
        @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
        if(ov || locked)$fatal(1,"FAIL: volatile overlay reset");
        for(i=0;i<703;i=i+1)read_both(i,initial_words[i]);
        // Five independent overlays, and reuse a hole only after the old
        // descriptor is no longer published. Abort/NO_SPACE never free it.
        for(j=0;j<5;j=j+1)begin
            slot=j;begin_song(1,48000,crc_record(32'hffffffff,one)^32'hffffffff,0);
            data=one;send(1,0);ack=1;send(2,0);ack=0;
            if(od[j*96+32+:11]!=703+j)$fatal(1,"FAIL: shared-pool allocation slot%0d",j);
        end
        slot=2;begin_song(1,48000,crc_record(32'hffffffff,one)^32'hffffffff,0);
        data=one;send(1,0);ack=1;send(2,0);ack=0;
        if(od[2*96+32+:11]!=708)$fatal(1,"FAIL: replacement overwrote its old extent");
        slot=0;begin_song(1,48000,crc_record(32'hffffffff,one)^32'hffffffff,0);
        data=one;send(1,0);ack=1;send(2,0);ack=0;
        if(od[32+:11]!=705 || ov!=31)$fatal(1,"FAIL: released extent was not reusable");
        @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
        crc=32'hffffffff;
        for(i=0;i<1345;i=i+1)crc=crc_record(crc,event_word(i*12000,1000,50+i%30,i%4,i));
        slot=4;begin_song(1345,16140000,crc^32'hffffffff,0);
        for(i=0;i<1345;i=i+1)begin data=event_word(i*12000,1000,50+i%30,i%4,i);send(1,0);end
        ack=1;send(2,0);ack=0;
        if(od[4*96+43+:12]!=1345 || od[4*96+:32]!=33625)$fatal(1,"FAIL: full-capacity metadata");
        begin_song(1,48000,0,2);
        for(i=0;i<2048;i=i+1)read_both(i,expected[i]);
        $display("PASS: writable DPB %0d port reads; frozen initial image, all96/group/page writes, five-slot allocation/replacement/hole reuse/full1345 pool; %0d responses, CRC/interval/range/density/count/timeout/abort/reset; old directory preserved; ack-atomic publication",port_reads,tests);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: P3 storage watchdog");end
endmodule
