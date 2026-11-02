`timescale 1ns/1ps
// Complete production top and actual complete VG, driven only through UART pins.
// Touch-controller registered readiness is explicit stimulus, as in the prior
// full-system checks; all notes, frames, CRCs, RAM and catalog publication run normally.
module tb_dual_uart_gate_accelerated;
    localparam BLE_BIT=24,USB_BIT=50;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;
    always #10 clk=~clk;always #40.690104 ac=~ac;
    reg [1:0] rx=3;
    wire [1:0] tx,rtx;
    tri [3:0] grow,rrow;
    tri1 gscl,gsda,gint,rscl,rsda,rint,giscl,gisda,riscl,risda;
    `define COMMON .audio_clk_12m288(ac),.sys_clk_50m(clk),.USER_BUTTON1_n(1'b1),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1),.COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led(),.song_uart_rx(rx[0]),.usb_song_uart_rx(rx[1]), \
        .dac_bclk(),.dac_lrck(),.dac_din(),.pa_en_n(),.i2s_bclk(),.i2s_ws(),.i2s_data(), \
        .lcd_pclk(),.lcd_hsync(),.lcd_vsync(),.lcd_de(),.lcd_backlight(),.lcd_r(),.lcd_g(),.lcd_b()
    neo_guitar_touch_game_top gate(`COMMON,.song_uart_tx(tx[0]),.usb_song_uart_tx(tx[1]), 
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]), 
        .ctp_scl(gscl),.ctp_sda(gsda),.ctp_int(gint),.ctp_rst_n(),.imu_scl(giscl),.imu_sda(gisda));
    rtlref_neo_guitar_touch_game_top reference(`COMMON,.song_uart_tx(rtx[0]),.usb_song_uart_tx(rtx[1]), 
        .ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]), 
        .ctp_scl(rscl),.ctp_sda(rsda),.ctp_int(rint),.ctp_rst_n(),.imu_scl(riscl),.imu_sda(risda));
    `undef COMMON
    wire rst=reference.lcd_rst_n;
    always @(posedge clk)begin #2;
        if(rst && tx!==rtx)$fatal(1,"FAIL: complete VG/RTL UART outputs differ");
    end
    integer bytes[0:1],host_sequence[0:1],session[0:1],packets=0,writes=0;
    reg [7:0] received[0:1][0:8191];
    reg [127:0] reply[0:1];
    always @(posedge clk)if(reference.score_write)writes=writes+1;
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
    initial begin
        `include "dual_uart_countdown.vh"
        force gate.u_touch.touch_ready=1'b1;
        force reference.u_touch.ready=1'b1;
        bytes[0]=0;bytes[1]=0;host_sequence[0]=0;host_sequence[1]=0;session[0]=101;session[1]=202;
        wait(rst);repeat(100)@(negedge clk);
        note={16'd0,16'hbeef,8'd0,8'd2,8'd0,8'd60,32'd12000,32'd0};
        begin_ble={32'd0,song_crc(note),32'd24000,16'd1,8'd1,8'd3};
        begin_usb={32'd0,song_crc(note),32'd24000,16'd1,8'd2,8'd4};
        fork transact(0,1,0);transact(1,1,0);join
        transact(1,3,begin_usb);
        transact(0,3,begin_ble,1);
        transact(1,4,note);transact(1,4,note,0,0,1);
        transact(1,5,0);transact(1,5,0,0,0,1);
        transact(0,2,4);
        if(reply[0][115:112]!==7 || reply[0][96:95]!==2)$fatal(1,"FAIL: actual USB import not visible to BLE");
        transact(0,3,begin_ble);transact(1,6,0,1);
        transact(0,4,note);transact(0,5,0);transact(0,5,0,0,0,1);
        transact(1,2,3);
        if(reply[1][115:112]!==7 || reply[1][96:95]!==1)$fatal(1,"FAIL: actual BLE import not visible to USB");
        if(packets!=15 || writes!=2)$fatal(1,"FAIL: UART gate coverage packets=%0d writes=%0d",packets,writes);
        $display("PASS: complete actual VG vs RTL; 15 UART frames with audited timer-Q acceleration, USB and BLE imports, cross-query, foreign abort BUSY, duplicate DATA/COMMIT, actual BSRAM CRC/group and CDC; touch readiness and counter high bits are explicit stimuli; real-baud RTL tested separately");
        $finish;
    end
    initial begin #(64'd3000000000);$fatal(1,"FAIL: dual UART gate watchdog");end
endmodule
