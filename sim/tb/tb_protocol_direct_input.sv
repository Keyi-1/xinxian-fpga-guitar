`timescale 1ns/1ps
// Four-row staging vs the frozen 16-row FIFO, under stop-and-wait traffic.
module tb_protocol_direct_input;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,rst=0,rv=0,re=0,tr=0,locked=0;
    reg [7:0] rd=0;
    always #10 clk=~clk;
    reg rv_delayed=0,re_delayed=0;reg [7:0] rd_delayed=0;
    always @(posedge clk)begin
        if(!rst)begin rv_delayed<=0;re_delayed<=0;rd_delayed<=0;end
        else begin rv_delayed<=rv;re_delayed<=re;rd_delayed<=rd;end
    end
    wire [1:0] tv,cv,cr;
    wire [7:0] td[0:1];wire [1:0] cmd[0:1],tone[0:1];wire [2:0] slot[0:1];
    wire [11:0] count[0:1];wire [31:0] duration[0:1],expected[0:1];wire [127:0] record_data[0:1];
    wire [15:0] errors[0:1];
    reg [2:0] response_pipe=0;
    always @(posedge clk)response_pipe<=rst ? {response_pipe[1:0],cv[0]} : 0;
    `define COMMON .clk(clk),.rst_n(rst),.tx_ready(tr), \
        .cmd_ready(1'b1),.response_valid(response_pipe[1]),.response_code(4'd0),.locked(locked), \
        .overlay_valid(5'd0),.overlay_data(480'd0)
    game_p3_protocol #(.FRAME_TIMEOUT(128),.DIRECT_INPUT(1)) compact(`COMMON,.rx_valid(rv_delayed),.rx_error(re_delayed),.rx_data(rd_delayed),.tx_valid(tv[0]),.tx_data(td[0]),.cmd_valid(cv[0]),.cmd(cmd[0]),
        .slot(slot[0]),.event_count(count[0]),.duration(duration[0]),.expected_crc(expected[0]),.timbre(tone[0]),.record_data(record_data[0]),.error_count(errors[0]),
        .query_request(),.query_slot(),.query_ready(1'b0),.query_body(120'd0),
        .context_load(1'b0),.context_data(234'd0),.context_state(),.frame_idle(),.rx_ready());
    fifo_reference_protocol #(.FRAME_TIMEOUT(128)) reference(`COMMON,.rx_valid(rv),.rx_error(re),.rx_data(rd),.tx_valid(tv[1]),.tx_data(td[1]),.cmd_valid(cv[1]),.cmd(cmd[1]),
        .slot(slot[1]),.event_count(count[1]),.duration(duration[1]),.expected_crc(expected[1]),.timbre(tone[1]),.record_data(record_data[1]),.error_count(errors[1]));
    `undef COMMON
    integer cycles=0,frames=0,commands=0,tx_bytes=0,max_queued=0;
    reg compare=1;
    reg [31:0] random_bits=32'h8b2391a7;
    always @(negedge clk)begin
        random_bits={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
        tr=|random_bits[3:1];
    end
    always @(posedge clk)begin
        if(rst)begin
            if(tv[0] && tr)tx_bytes=tx_bytes+1;
            if(cv[0])commands=commands+1;
            if(reference.used>max_queued)max_queued=reference.used;
            if(compact.poisoned)$fatal(1,"FAIL: four-row FIFO overflow under stop-and-wait");
        end
        #2;
        if(rst && compare)begin
            cycles=cycles+1;
            if(tv[0]!==tv[1] || cv[0]!==cv[1] || errors[0]!==errors[1])$fatal(1,"FAIL: FIFO external equivalence cycle%0d",cycles);
            if(tv[0] && td[0]!==td[1])$fatal(1,"FAIL: FIFO TX byte");
            if({compact.crc,compact.tx_crc}!=={reference.crc,reference.tx_crc})$fatal(1,"FAIL: shared RX/TX CRC state");
            if(cv[0] && {cmd[0],slot[0],count[0],duration[0],expected[0],tone[0],record_data[0]}!==
                         {cmd[1],slot[1],count[1],duration[1],expected[1],tone[1],record_data[1]})$fatal(1,"FAIL: FIFO command");
            if(compact.state!==reference.state)$fatal(1,"FAIL: direct-input parser FSM");
            if(reference.pop && compact.byte_value!==reference.byte_value)$fatal(1,"FAIL: FIFO head bytes");
        end
    end
    function automatic [31:0] crc_byte(input [31:0] prior,input [7:0] b);
        reg [31:0] v;integer k;
        begin v=prior^b;for(k=0;k<8;k=k+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
    endfunction
    task automatic byte_send(input [7:0] b);
        begin @(negedge clk);rd=b;rv=1;@(negedge clk);rv=0;repeat(2)@(negedge clk);end
    endtask
    task automatic transact(input [7:0] op,input [15:0] seq,input [127:0] payload,input bit corrupt=0);
        reg [7:0] b[0:31];reg [31:0] crc;integer i,first;
        begin
            first=tx_bytes;
            for(i=0;i<32;i=i+1)b[i]=0;
            b[0]=8'h58;b[1]=8'h47;b[2]=8'h33;b[3]=8'h21;b[4]=3;b[5]=op;b[6]=11;b[8]=seq;b[9]=seq>>8;
            for(i=0;i<16;i=i+1)b[10+i]=payload[i*8+:8];
            crc=32'hffffffff;for(i=4;i<28;i=i+1)crc=crc_byte(crc,b[i]);crc=crc^32'hffffffff;
            for(i=0;i<4;i=i+1)b[28+i]=crc[i*8+:8];
            if(corrupt)b[28]=b[28]^1;
            for(i=0;i<32;i=i+1)byte_send(b[i]);
            wait(tx_bytes>=first+32);repeat(2)@(negedge clk);frames=frames+1;
        end
    endtask
    integer i,seq;reg [7:0] op;reg [127:0] payload;reg corrupt;
    initial begin
        repeat(5)@(negedge clk);rst=1;seq=0;
        transact(1,seq,0);seq=1;
        for(i=0;i<1024;i=i+1)begin
            op=2+i%6;payload=0;
            if(op==2)payload=i%5;
            if(op==3)payload={32'd0,32'hba027e12,32'd24000,16'd1,8'd1,8'd3};
            if(op==4)payload={16'd0,i[15:0],8'd0,8'd2,8'd0,8'd60,32'd12000,32'd0};
            corrupt=i%17==0;
            transact(op,seq,payload,corrupt);
            if(!corrupt)seq=seq+1;
        end
        if(frames!=1025 || commands<500 || max_queued<1 || max_queued>2)$fatal(1,"FAIL: bounded FIFO coverage %0d/%0d/%0d",frames,commands,max_queued);
        $display("PASS: direct replay vs frozen buffered parser (one ingress clock aligned), exact cycle/TX/command/error equality on %0d stop-and-wait frames, %0d commands, CRC failures, randomized TX backpressure, byte spacing4clks, queued_max=%0d",frames,commands,max_queued);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: bounded FIFO watchdog");end
endmodule
