`timescale 1ns/1ps
module tb_game_p3_frame_rx;
    reg clk=0,rst=0,rv=0,re=0,take=0;
    reg [7:0] value;
    always #10 clk=~clk;
    wire ready;wire [223:0] data;wire [15:0] errors;
    game_p3_frame_rx #(.FRAME_TIMEOUT(32)) dut(.clk(clk),.rst_n(rst),.rx_valid(rv),.rx_error(re),.rx_data(value),.take(take),.ready(ready),.data(data),.errors(errors));
    task automatic put(input [7:0] b);
        begin @(negedge clk);value=b;rv=1;@(negedge clk);rv=0;end
    endtask
    task automatic magic;
        begin put(8'h58);put(8'h47);put(8'h33);put(8'h21);end
    endtask
    task automatic release_frame;
        begin @(negedge clk);take=1;@(negedge clk);take=0;if(ready)$fatal(1,"FAIL: frame take");end
    endtask
    integer n;reg [223:0] expected;
    initial begin
        repeat(4)@(negedge clk);rst=1;
        put(8'ha8);put(8'h58);magic;
        for(n=0;n<28;n=n+1)begin
            expected[n*8+:8]=n*7+13;put(n*7+13);
            if(n<27 && ready)$fatal(1,"FAIL: partial frame published");
        end
        if(!ready || data!==expected)$fatal(1,"FAIL: complete frame staging");
        put(8'h91);put(8'h92);
        if(!ready || data!==expected || errors!=2)$fatal(1,"FAIL: complete frame overwritten");
        re=1;@(negedge clk);re=0;
        if(!ready || data!==expected || errors!=3)$fatal(1,"FAIL: queued frame lost on unrelated framing error");
        release_frame();magic;for(n=0;n<5;n=n+1)put(n);
        repeat(40)@(negedge clk);
        if(ready || dut.receiving || errors!=4)$fatal(1,"FAIL: partial timeout recovery");
        magic;for(n=0;n<3;n=n+1)put(n);
        re=1;@(negedge clk);re=0;
        if(ready || dut.receiving || errors!=5)$fatal(1,"FAIL: framing error recovery");
        magic;for(n=0;n<28;n=n+1)begin expected[n*8+:8]=8'ha5^n;put(8'ha5^n);end
        if(!ready || data!==expected)$fatal(1,"FAIL: stale partial bytes");
        release_frame();magic;put(8'h99);rst=0;repeat(2)@(negedge clk);rst=1;
        if(ready || errors!=0)$fatal(1,"FAIL: reset partial frame");
        magic;for(n=0;n<28;n=n+1)begin expected[n*8+:8]=n;put(n);end
        if(!ready || data!==expected)$fatal(1,"FAIL: post-reset complete frame");
        $display("PASS: frame staging exact28 bytes, overlapping magic, no partial publication, retained pending data under overflow/framing error, timeout/framing/reset resync; no BSRAM");
        $finish;
    end
    initial begin #100000;$fatal(1,"FAIL: frame staging watchdog");end
endmodule
