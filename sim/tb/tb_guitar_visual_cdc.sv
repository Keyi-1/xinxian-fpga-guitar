`timescale 1ns/1ps
module tb_guitar_visual_cdc;
    reg src_clk=0,dst_clk=0,rst_n=0,request=0;
    always #7 src_clk=~src_clk;
    always #10 dst_clk=~dst_clk;
    reg [7:0] serial=0;
    wire [399:0] data={50{serial}};
    wire [399:0] received;
    wire update;
    guitar_visual_cdc dut(.src_clk(src_clk),.src_rst_n(rst_n),.src_snapshot(data),
        .dst_clk(dst_clk),.dst_rst_n(rst_n),.dst_request(request),.dst_snapshot(received),.dst_update(update));
    always @(posedge src_clk) if(rst_n) serial<=serial+1'b1;
    integer copies=0,j;
    reg [399:0] old_data=0;
    always @(posedge dst_clk) begin
        #1;
        if(rst_n) begin
            if(update) begin
                copies++;
                for(j=1;j<50;j++)
                    if(received[j*8+:8]!=received[7:0]) $fatal(1,"FAIL: torn CDC snapshot");
            end else if(received!==old_data) $fatal(1,"FAIL: mailbox changed without update");
            old_data=received;
        end
    end
    integer k;
    initial begin
        repeat(5) @(negedge dst_clk);rst_n=1;
        for(k=0;k<20;k++) begin
            @(negedge dst_clk);request=1;
            @(negedge dst_clk);request=0;
            repeat(35) @(negedge dst_clk);
        end
        if(copies!=20) $fatal(1,"FAIL: missing CDC snapshots %0d",copies);
        $display("PASS: 20 atomic 400-bit mailbox transfers under asynchronous changing inputs");$finish;
    end
    initial begin #100000;$fatal(1,"FAIL: CDC timeout");end
endmodule
