    // Independent bit-level UART receiver, not the DUT's RX implementation.
    integer bit_index;reg [7:0] capture;
    initial forever begin
        @(negedge tx);
        if(rst)begin
            repeat(BIT+BIT/2)@(posedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                #1;capture[bit_index]=tx;repeat(BIT)@(posedge clk);
            end
            #1;if(!tx)$fatal(1,"FAIL: device TX stop bit");
            received[rx_count]=capture;rx_count=rx_count+1;
        end
    end
    function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] b);
        reg [31:0] v;integer k;
        begin v=prior^b;for(k=0;k<8;k=k+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
    endfunction
    function automatic [31:0] crc_record(input [31:0] prior,input [127:0] word);
        reg [31:0] v;integer k;
        begin v=prior;for(k=0;k<16;k=k+1)v=crc_byte(v,word[k*8+:8]);crc_record=v;end
    endfunction
    task automatic byte_send(input [7:0] value,input integer period=BIT,input bit good_stop=1);
        integer b;
        begin
            @(negedge clk);rx=0;repeat(period)@(negedge clk);
            for(b=0;b<8;b=b+1)begin rx=value[b];repeat(period)@(negedge clk);end
            rx=good_stop;repeat(period)@(negedge clk);rx=1;
        end
    endtask
    reg [127:0] last_reply;
    task automatic transact(input [7:0] op,input [15:0] session,seq,
        input [127:0] body,input integer status,input bit corrupt=0,input integer period=BIT);
        reg [7:0] frame[0:31];reg [31:0] check;integer k,first;
        begin
            frame[0]=8'h58;frame[1]=8'h47;frame[2]=8'h33;frame[3]=8'h21;
            frame[4]=3;frame[5]=op;frame[6]=session[7:0];frame[7]=session[15:8];frame[8]=seq[7:0];frame[9]=seq[15:8];
            for(k=0;k<16;k=k+1)frame[10+k]=body[k*8+:8];frame[26]=0;frame[27]=0;
            check=32'hffffffff;for(k=4;k<28;k=k+1)check=crc_byte(check,frame[k]);check=check^32'hffffffff;
            for(k=0;k<4;k=k+1)frame[28+k]=check[k*8+:8];
            if(corrupt)frame[10]=frame[10]^1;
            first=rx_count;
            for(k=0;k<32;k=k+1)byte_send(frame[k],period);
            wait(rx_count>=first+32);
            if(received[first]!=8'h58 || received[first+1]!=8'h47 || received[first+2]!=8'h33 || received[first+3]!=8'h21 ||
               received[first+4]!=3 || received[first+5]!=(op|8'h80) ||
               {received[first+7],received[first+6]}!=session || {received[first+9],received[first+8]}!=seq || received[first+10]!=status)
                $fatal(1,"FAIL: response frame op%0d seq%0d status%0d wanted%0d",op,seq,received[first+10],status);
            check=32'hffffffff;for(k=4;k<28;k=k+1)check=crc_byte(check,received[first+k]);check=check^32'hffffffff;
            if({received[first+31],received[first+30],received[first+29],received[first+28]}!==check)$fatal(1,"FAIL: response CRC");
            for(k=0;k<16;k=k+1)last_reply[k*8+:8]=received[first+10+k];
            packets=packets+1;repeat(BIT)@(negedge clk);
        end
    endtask
