`timescale 1ns/1ps
module tb_jdy23_uart_9600;
    localparam BIT=5208;
    reg clk=0,rst_n=0,rx=1,tx_valid=0;
    reg [7:0] tx_data=0;
    wire tx,rx_valid,framing_error,tx_ready;
    wire [7:0] rx_data;
    integer received=0,errors=0,tx_received=0;
    reg [7:0] data[0:63],out[0:63],frame[0:31];
    always #10 clk=~clk;
    game_p3_uart #(.CLKS_PER_BIT(BIT)) dut(.*);
    always @(posedge clk)begin
        if(rx_valid)begin data[received]=rx_data;received=received+1;end
        if(framing_error)errors=errors+1;
    end
    integer i,b;reg [7:0] capture;
    initial forever begin
        @(negedge tx);
        repeat(BIT+BIT/2)@(posedge clk);
        for(b=0;b<8;b=b+1)begin #1;capture[b]=tx;repeat(BIT)@(posedge clk);end
        #1;if(tx!==1)$fatal(1,"FAIL: 9600 TX stop bit");
        out[tx_received]=capture;tx_received=tx_received+1;
    end
    task automatic send(input [7:0] value,input integer period=BIT,input bit good_stop=1);
        integer n;
        begin
            @(negedge clk);rx=0;repeat(period)@(negedge clk);
            for(n=0;n<8;n=n+1)begin rx=value[n];repeat(period)@(negedge clk);end
            rx=good_stop;repeat(period)@(negedge clk);rx=1;
        end
    endtask
    task automatic transmit(input [7:0] value);
        begin
            wait(tx_ready);@(negedge clk);tx_data=value;tx_valid=1;
            @(negedge clk);tx_valid=0;wait(!tx_ready);wait(tx_ready);
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)frame[i]=(i*37)^8'h58;
        frame[0]=8'h58;frame[1]=8'h47;frame[2]=8'h33;frame[3]=8'h21;
        repeat(6)@(negedge clk);rst_n=1;
        // The BLE module forwards a 32-byte frame as a paced 20+12 stream.
        for(i=0;i<20;i=i+1)send(frame[i]);
        repeat(750000)@(negedge clk); // 15ms module idle between fragments.
        for(i=20;i<32;i=i+1)send(frame[i]);
        repeat(BIT)@(negedge clk);
        if(received!=32||errors!=0)$fatal(1,"FAIL: fragmented RX count/errors");
        for(i=0;i<32;i=i+1)if(data[i]!==frame[i])$fatal(1,"FAIL: fragmented RX byte %0d",i);
        // Peer clock +/-2 percent: asynchronous module UART timing.
        send(8'ha5,5104);send(8'h5a,5312);repeat(BIT)@(negedge clk);
        if(received!=34||data[32]!==8'ha5||data[33]!==8'h5a)$fatal(1,"FAIL: baud tolerance");
        for(i=0;i<32;i=i+1)transmit(frame[i]);
        wait(tx_received==32);
        for(i=0;i<32;i=i+1)if(out[i]!==frame[i])$fatal(1,"FAIL: TX byte %0d",i);
        send(8'hff,BIT,0);repeat(BIT)@(negedge clk);
        if(errors!=1)$fatal(1,"FAIL: bad stop bit not rejected");
        send(8'hc3);repeat(BIT)@(negedge clk);
        if(received!=35||data[34]!==8'hc3)$fatal(1,"FAIL: RX recovery");
        $display("PASS: real 50MHz/5208 UART; 32-byte 20+12 RX; +/-2%% peer clocks; 32-byte TX; framing error/recovery");
        $finish;
    end
    initial begin #150000000;$fatal(1,"FAIL: watchdog");end
endmodule
