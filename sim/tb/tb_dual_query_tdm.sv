`timescale 1ns/1ps
module tb_dual_query_tdm;
    parameter REAL_BAUD=0;
    localparam BLE_BIT=8, USB_BIT=8;
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
    reg intentional_errors=0;
    always @(posedge clk)if(rst)begin
        if(dut.packet_ready[0])max_fifo0=1;
        if(dut.packet_ready[1])max_fifo1=1;
        if(!intentional_errors && dut.frontend_errors!==0)$fatal(1,"FAIL: frame buffer dropped legal query data");
        if(dut.context_load && !dut.core_idle)$fatal(1,"FAIL: query context switch while busy");
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
    task automatic check_slot(input integer port,input integer which);
        integer count_expected,duration_expected,timbre_expected,base_expected;
        begin
            case(which)
                0:begin count_expected=67;duration_expected=1620000;timbre_expected=0;base_expected=0;end
                1:begin count_expected=168;duration_expected=9216000;timbre_expected=2;base_expected=67;end
                2:begin count_expected=212;duration_expected=7296000;timbre_expected=1;base_expected=235;end
                default:begin count_expected=0;duration_expected=0;timbre_expected=0;base_expected=0;end
            endcase
            if(reply[port][111:104]!==which || reply[port][115:112] !== (which<3 ? 4'd3 : 4'd0) ||
               reply[port][62:51]!==count_expected || reply[port][94:63]!==duration_expected ||
               reply[port][96:95]!==timbre_expected || reply[port][50:40]!==base_expected ||
               reply[port][39:8]!==((duration_expected+479)/480))$fatal(1,"FAIL: independent query metadata port%0d slot%0d reply%h",port,which,reply[port]);
        end
    endtask
    task automatic bad_uart_byte;
        integer bit_number;
        begin
            @(negedge clk);rx[0]=0;repeat(BLE_BIT)@(negedge clk);
            for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin rx[0]=1'b1;repeat(BLE_BIT)@(negedge clk);end
            rx[0]=0;repeat(BLE_BIT)@(negedge clk);rx[0]=1;repeat(BLE_BIT*2)@(negedge clk);
        end
    endtask
    integer n,a,b;
    initial begin
        bytes[0]=0;bytes[1]=0;host_sequence[0]=0;host_sequence[1]=0;session[0]=101;session[1]=101;
        repeat(12)@(negedge clk);rst=1;repeat(12)@(negedge clk);
        fork transact(0,1,0);transact(1,1,0);join
        for(n=0;n<32;n=n+1)begin
            a=n%5;b=4-a;
            fork transact(0,2,a);transact(1,2,b);join
            check_slot(0,a);check_slot(1,b);
        end
        fork transact(0,2,a,0,0,1);transact(1,2,b,0,0,1);join
        check_slot(0,a);check_slot(1,b);
        fork transact(0,2,0);transact(1,2,4,12,1);join
        check_slot(0,0);transact(1,2,4);check_slot(1,4);
        fork transact(0,7,0);transact(1,7,0);join
        if(reply[0][63:48]!==0 || reply[1][63:48]!==1)$fatal(1,"FAIL: per-endpoint CRC error counters");
        fork transact(0,7,0,0,0,1);transact(1,7,0,0,0,1);join
        if(reply[0][63:48]!==0 || reply[1][63:48]!==1)$fatal(1,"FAIL: identical request cached STATUS contexts mixed");
        intentional_errors=1;bad_uart_byte();bad_uart_byte();
        fork transact(0,7,0);transact(1,7,0);join
        if(reply[0][63:48]!==2 || reply[1][63:48]!==1)$fatal(1,"FAIL: staged UART errors not applied to private context");
        if(parallel_queries<32 || packets!=77 || writes!=0 || sv!==0 || av!==0)$fatal(1,"FAIL: query contention coverage %0d packets%0d",parallel_queries,packets);
        $display("PASS: 77 physical-pin frames, 32 simultaneous distinct-slot query pairs; independent slot/base/count/duration/progress/timbre/flags, cached STATUS and private CRC/UART error counters; identical session IDs and independent TDM cache; contended cycles=%0d",parallel_queries);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: shared query watchdog");end
endmodule
