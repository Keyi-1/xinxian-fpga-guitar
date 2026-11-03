`timescale 1ns/1ps
module tb_dual_score_transport;
    parameter REAL_BAUD=0;
    localparam BLE_BIT=REAL_BAUD ? 5208 : 16, USB_BIT=REAL_BAUD ? 434 : 8;
    localparam TIMEOUT=REAL_BAUD ? 250000000 : 1000000;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0,rst=0,menu_idle=1;
    always #10 clk=~clk;always #40.690104 ac=~ac;
    reg [1:0] rx=3;
    wire [1:0] tx;
    wire locked,we,vr;
    wire [10:0] wa,va;
    wire [95:0] wd,vd,aud;
    wire [4:0] sv,av;
    wire [479:0] sd,ad;
    game_p3_dual_service #(.BLE_CLKS_PER_BIT(BLE_BIT),.USB_CLKS_PER_BIT(USB_BIT),.IMPORT_TIMEOUT_CYCLES(TIMEOUT)) dut(
        .clk(clk),.rst_n(rst),.audio_clk(ac),.audio_rst_n(rst),.ble_rx(rx[0]),.usb_rx(rx[1]),.ble_tx(tx[0]),.usb_tx(tx[1]),
        .audio_idle(1'b1),.menu_idle(menu_idle),.frame_begin(1'b1),.locked(locked),
        .write_enable(we),.write_address(wa),.write_data(wd),.verify_read(vr),.verify_address(va),.verify_data(vd),
        .system_valid(sv),.audio_valid(av),.system_data(sd),.audio_data(ad));
    game_p3_score_bank bank(.audio_clk(ac),.audio_read(1'b0),.audio_address(11'd0),.audio_data(aud),
        .display_clk(clk),.display_read(vr),.display_address(va),.display_data(vd),.write_enable(we),.write_address(wa),.write_data(wd));
    integer bytes[0:1],host_sequence[0:1],session[0:1],packets=0,writes=0,parallel_queries=0,max_fifo0=0,max_fifo1=0;
    reg [7:0] received[0:1][0:8191];
    reg [127:0] reply[0:1];
    always @(posedge clk)if(we)writes=writes+1;
    always @(posedge clk)if(dut.query_request==2'b11)parallel_queries=parallel_queries+1;
    always @(posedge clk)if(rst)begin
        if(dut.packet_ready[0])max_fifo0=1;
        if(dut.packet_ready[1])max_fifo1=1;
        if(dut.frontend_errors!==0)$fatal(1,"FAIL: valid stop-and-wait traffic overflowed a frame buffer");
        if(dut.context_load && !dut.core_idle)$fatal(1,"FAIL: context switch while parser active");
    end
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:monitor
        localparam PERIOD=g==0 ? BLE_BIT : USB_BIT;
        integer bit_index;reg [7:0] value;
        initial forever begin
            @(negedge tx[g]);
            if(rst)begin
                repeat(PERIOD+PERIOD/2)@(posedge clk);
                for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                    #1;value[bit_index]=tx[g];repeat(PERIOD)@(posedge clk);
                end
                #1;if(!tx[g])$fatal(1,"FAIL: port%0d bad stop",g);
                received[g][bytes[g]]=value;bytes[g]=bytes[g]+1;
            end
        end
    end endgenerate
    function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] b);
        reg [31:0] v;integer k;
        begin v=prior^b;for(k=0;k<8;k=k+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
    endfunction
    function automatic [31:0] song_crc(input [127:0] word);
        reg [31:0] v;integer k;
        begin v=32'hffffffff;for(k=0;k<16;k=k+1)v=crc_byte(v,word[k*8+:8]);song_crc=v^32'hffffffff;end
    endfunction
    task automatic transact(input integer port,input [7:0] op,input [127:0] payload,
                            input integer wanted=0,input bit corrupt=0,input bit duplicate=0);
        reg [7:0] frame[0:31];reg [31:0] crc;
        integer i,b,period,first,seq;
        begin
            period=port==0 ? BLE_BIT : USB_BIT;first=bytes[port];seq=host_sequence[port]-duplicate;
            frame[0]=8'h58;frame[1]=8'h47;frame[2]=8'h33;frame[3]=8'h21;
            frame[4]=3;frame[5]=op;frame[6]=session[port];frame[7]=session[port]>>8;frame[8]=seq;frame[9]=seq>>8;
            for(i=0;i<16;i=i+1)frame[10+i]=payload[i*8+:8];frame[26]=0;frame[27]=0;
            crc=32'hffffffff;for(i=4;i<28;i=i+1)crc=crc_byte(crc,frame[i]);crc=crc^32'hffffffff;
            for(i=0;i<4;i=i+1)frame[28+i]=crc[i*8+:8];
            if(corrupt)frame[10]=frame[10]^1;
            for(i=0;i<32;i=i+1)begin
                @(negedge clk);rx[port]=0;repeat(period)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx[port]=frame[i][b];repeat(period)@(negedge clk);end
                rx[port]=1;repeat(period)@(negedge clk);
            end
            wait(bytes[port]>=first+32);
            for(i=0;i<10;i=i+1)if(received[port][first+i] !== (i==5 ? (op|8'h80) : frame[i]))
                $fatal(1,"FAIL: port%0d response header byte%0d",port,i);
            if(received[port][first+10]!==wanted)$fatal(1,"FAIL: port%0d op%0d seq%0d status%0d wanted%0d",port,op,seq,received[port][first+10],wanted);
            crc=32'hffffffff;for(i=4;i<28;i=i+1)crc=crc_byte(crc,received[port][first+i]);crc=crc^32'hffffffff;
            for(i=0;i<4;i=i+1)if(received[port][first+28+i]!==crc[i*8+:8])$fatal(1,"FAIL: ACK CRC");
            for(i=0;i<16;i=i+1)reply[port][i*8+:8]=received[port][first+10+i];
            packets=packets+1;
            if(wanted==0 && !duplicate)host_sequence[port]=host_sequence[port]+1;
            repeat(period)@(negedge clk);
        end
    endtask
    reg [127:0] note,begin_ble,begin_usb;
    integer i,previous_writes,saved_seq;
    initial begin
        bytes[0]=0;bytes[1]=0;host_sequence[0]=0;host_sequence[1]=0;session[0]=101;session[1]=202;
        repeat(12)@(negedge clk);rst=1;repeat(12)@(negedge clk);
        note={16'd0,16'hbeef,8'd0,8'd2,8'd0,8'd60,32'd12000,32'd0};
        begin_ble={32'd0,song_crc(note),32'd24000,16'd1,8'd1,8'd3};
        begin_usb={32'd0,song_crc(note),32'd24000,16'd1,8'd2,8'd4};
        fork transact(0,1,0);transact(1,1,0);join
        fork
            transact(0,2,0);
            begin repeat((639*(BLE_BIT-USB_BIT))/2)@(negedge clk);transact(1,2,0);end
        join
        if(parallel_queries==0)$fatal(1,"FAIL: shared query arbiter not contended");
        for(i=0;i<5;i=i+1)begin
            transact(0,2,i);
            if(i<3 && reply[0][115:112]!==4'b0011)$fatal(1,"FAIL: builtin flags");
            if(i>=3 && reply[0][115:8]!=={i[7:0],96'd0})$fatal(1,"FAIL: pending slot descriptor");
        end
        transact(0,3,begin_ble);
        transact(1,2,3);if(reply[1][115:112]!==0)$fatal(1,"FAIL: unpublished BLE song visible");
        transact(1,3,begin_usb,1);transact(1,4,note,1);transact(1,5,0,1);transact(1,6,0,1);
        saved_seq=host_sequence[1];session[1]=303;host_sequence[1]=0;transact(1,1,0,1);session[1]=202;host_sequence[1]=saved_seq;
        transact(1,4,note,12,1);if(!locked || writes!=0)$fatal(1,"FAIL: foreign port altered owner");
        transact(0,4,note);previous_writes=writes;transact(0,4,note,0,0,1);
        if(writes!=previous_writes)$fatal(1,"FAIL: duplicate DATA written twice");
        transact(0,5,0);transact(0,5,0,0,0,1);wait(av[3]);
        transact(1,2,3);
        if(reply[1][115:112]!==7 || reply[1][96:95]!==1 || reply[1][62:51]!==1)$fatal(1,"FAIL: BLE commit descriptor");
        transact(1,3,begin_usb);
        transact(0,3,begin_ble,1);transact(0,4,note,1);transact(0,6,0,1);
        transact(1,4,note);transact(1,5,0);transact(1,5,0,0,0,1);wait(av[4]);
        transact(0,2,4);if(reply[0][115:112]!==7 || reply[0][96:95]!==2)$fatal(1,"FAIL: USB commit descriptor");
        fork transact(0,3,begin_ble,1);transact(1,3,begin_usb);join
        transact(1,6,0);if(locked)$fatal(1,"FAIL: owner abort");
        transact(0,3,begin_ble);transact(0,6,0);
        menu_idle=0;transact(0,3,begin_ble,1);transact(1,3,begin_usb,1);menu_idle=1;
        if(!REAL_BAUD)begin
            transact(0,3,begin_ble);repeat(TIMEOUT+20)@(negedge clk);
            if(locked)$fatal(1,"FAIL: abandoned transaction never released");
            transact(1,3,begin_usb);transact(1,6,0);transact(0,4,note,9);
        end
        if(sv!==5'b11000 || av!==5'b11000 || writes!=2)$fatal(1,"FAIL: final atomic bank/CDC/write count");
        if(packets!=(REAL_BAUD ? 37 : 41))$fatal(1,"FAIL: coverage real=%0d packets=%0d",REAL_BAUD,packets);
        if(max_fifo0!=1 || max_fifo1!=1)$fatal(1,"FAIL: frame staging coverage %0d/%0d",max_fifo0,max_fifo1);
        $display("Frame coverage: queued_max BLE=%0d USB=%0d one packet each; contended_query_cycles=%0d",max_fifo0,max_fifo1,parallel_queries);
        $display("PASS: dual UART real_baud=%0d packets=%0d writes=%0d; independent sessions/ACKs, 3+2 slots, bidirectional BUSY ownership, corrupt packets, duplicate DATA/COMMIT, concurrent requests, abort/menu guard/timeout, actual DPB CRC and CDC",REAL_BAUD,packets,writes);
        $finish;
    end
    initial begin #(64'd10000000000);$fatal(1,"FAIL: dual UART watchdog");end
endmodule
