// Same real UART/CRC/RAM/CDC regression, applied separately to new import slots4 and5.
`timescale 1ns/1ps
module tb_song_slots_uart #(parameter [7:0] IMPORT_SLOT=4);
    GSR GSR(.GSRI(1'b1));
    localparam BIT=24;
    reg clk=0,ac=0,rst=0,rx=1,allowed=1;
    always #5 clk=~clk;always #7 ac=~ac;
    wire tx,rb,fe,tv,tr,cv,cr,rv,locked,we,pub,ack;
    wire [7:0] rd,td;wire [1:0] cmd,timbre;wire [2:0] slot,cs;
    wire [11:0] count;wire [31:0] duration,crc;
    wire [127:0] record;wire [3:0] code;
    wire [10:0] wa;wire [95:0] wd,desc;wire [4:0] ov,av;
    wire verify_read;wire [10:0] verify_address;
    wire [95:0] audio_word,display_word;
    wire [479:0] od,ad;wire [15:0] errors;
    integer rx_count=0,writes=0,packets=0;
    reg [7:0] received[0:4095];
    game_p3_uart #(.CLKS_PER_BIT(BIT)) phy(.clk(clk),.rst_n(rst),.rx(rx),.tx(tx),
        .rx_valid(rb),.rx_data(rd),.framing_error(fe),.tx_valid(tv),.tx_data(td),.tx_ready(tr));
    game_p3_protocol #(.FRAME_TIMEOUT(1500)) protocol(.clk(clk),.rst_n(rst),.rx_valid(rb),.rx_error(fe),.rx_data(rd),
        .tx_valid(tv),.tx_data(td),.tx_ready(tr),.cmd_valid(cv),.cmd_ready(cr),.cmd(cmd),
        .slot(slot),.event_count(count),.duration(duration),.expected_crc(crc),.timbre(timbre),.record_data(record),
        .response_valid(rv),.response_code(code),.locked(locked),.overlay_valid(ov),.overlay_data(od),.error_count(errors));
    game_p3_import #(.TIMEOUT_CYCLES(200000)) importer(.clk(clk),.rst_n(rst),.import_allowed(allowed),
        .cmd_valid(cv),.cmd_ready(cr),.cmd(cmd),.slot(slot),.event_count(count),.duration(duration),.expected_crc(crc),.timbre(timbre),
        .record_data(record),.response_valid(rv),.response_code(code),.locked(locked),.write_enable(we),.write_address(wa),.write_data(wd),
        .verify_read(verify_read),.verify_address(verify_address),.verify_data(display_word),
        .commit_valid(pub),.commit_ready(ack),.commit_slot(cs),.commit_descriptor(desc),.overlay_valid(ov),.overlay_data(od));
    game_p3_catalog_cdc cdc(.src_clk(clk),.src_rst_n(rst),.valid(pub),.slot(cs),.descriptor(desc),.ready(ack),
        .dst_clk(ac),.dst_rst_n(rst),.overlay_valid(av),.overlay_data(ad));
    reg ar=0,dr=0;reg [10:0] aa=0,da=0;
    game_p3_score_bank bank(.audio_clk(ac),.audio_read(ar),.audio_address(aa),.audio_data(audio_word),
        .display_clk(clk),.display_read(dr || verify_read),.display_address(verify_read ? verify_address : da),.display_data(display_word),
        .write_enable(we),.write_address(wa),.write_data(wd));
    wire valid,playable,test_only;wire [10:0] base;wire [11:0] events;
    wire [31:0] song_duration,step;wire [1:0] tone;
    game_p3_catalog catalog(.slot(IMPORT_SLOT[2:0]),.overlay_valid(av),.overlay_data(ad),.valid(valid),.playable(playable),.test_only(test_only),
        .base(base),.event_count(events),.duration(song_duration),.progress_step(step),.timbre(tone));
    always @(posedge clk)if(we)writes=writes+1;
    `include "game_p3_uart_host.vh"
    reg [127:0] one,two,begin_payload;reg [31:0] song_crc;integer k;
    initial begin
        repeat(8)@(negedge clk);rst=1;
        one={16'd0,16'hbeef,8'd0,8'd2,8'd0,8'd79,32'd12000,32'd0};
        two={16'd0,16'h1234,8'd0,8'd2,8'd1,8'd50,32'd12000,32'd24000};
        song_crc=crc_record(crc_record(32'hffffffff,one),two)^32'hffffffff;
        if(song_crc!==32'h62885540)$fatal(1,"FAIL: independent Python/zlib golden song CRC");
        begin_payload={32'd0,song_crc,32'd48000,16'd2,8'd1,IMPORT_SLOT};
        transact(1,17,0,0,0);
        transact(2,17,1,{120'd0,IMPORT_SLOT},0);
        if(last_reply[115:112]!==4'd0 || last_reply[103:8]!==96'd0 || last_reply[111:104]!==IMPORT_SLOT)
            $fatal(1,"FAIL: pending slot QUERY exposes builtin/diagnostic descriptor");
        transact(3,17,2,begin_payload,0);
        transact(4,17,3,one,0);
        transact(4,17,3,one,0);if(writes!=1)$fatal(1,"FAIL: duplicate DATA wrote twice");
        transact(4,17,3,two,13);if(writes!=1)$fatal(1,"FAIL: changed duplicate accepted");
        transact(4,17,4,two,12,1);if(writes!=1)$fatal(1,"FAIL: corrupt packet wrote");
        transact(4,17,4,two,0);
        transact(5,17,5,0,0);
        if(ov!==av || od!==ad || !playable || test_only || base!=703 || events!=2 || song_duration!=48000 || tone!=1 || step!=100)
            $fatal(1,"FAIL: CDC/runtime catalog");
        transact(5,17,5,0,0);if(writes!=2)$fatal(1,"FAIL: repeated COMMIT rewrote bank");
        transact(2,17,6,{120'd0,IMPORT_SLOT},0);
        if(last_reply[115:112]!==4'b0111)$fatal(1,"FAIL: imported slot QUERY flags");
        if(last_reply[103:8]!==od[IMPORT_SLOT*96+:96])$fatal(1,"FAIL: LIST runtime descriptor");
        transact(7,17,8,0,13);
        transact(6,17,7,0,0);
        // False start, malformed stop and partial-frame timeout all recover.
        @(negedge clk);rx=0;repeat(4)@(negedge clk);rx=1;repeat(BIT*2)@(negedge clk);
        byte_send(8'h37,BIT,0);repeat(BIT*12)@(negedge clk);
        byte_send(8'h58);byte_send(8'h47);byte_send(8'h33);byte_send(8'h21);byte_send(3);
        repeat(1600)@(negedge clk);
        transact(1,18,0,0,0,0,BIT+1);
        allowed=0;transact(3,18,1,begin_payload,1);allowed=1;
        transact(3,18,1,begin_payload,0,0,BIT-1);transact(6,18,2,0,0);
        @(negedge ac);aa=703;ar=1;@(posedge ac);#1;
        if(audio_word!=={16'hbeef,5'd0,2'd2,2'd0,7'd79,32'd12000,32'd0})$fatal(1,"FAIL: UART data not in bank");
        @(negedge ac);ar=0;
        if(errors<5 || locked)$fatal(1,"FAIL: error accounting/unlock");
        $display("PASS: %0d real-wire request/ACK packets, independent UART bit/CRC oracle, continuous bytes, baud offset, false start/bad stop/partial timeout, duplicate DATA/COMMIT, changed replay/sequence/CRC/BUSY, writable DPB and async catalog commit",packets);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: UART import watchdog state%0d rx_count%0d",protocol.state,rx_count);end
endmodule
