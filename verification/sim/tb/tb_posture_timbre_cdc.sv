`timescale 1ns/1ps
module tb_posture_timbre_cdc;
    reg src=0,dst=0;always #5 src=~src;always #7 dst=~dst;
    reg rst_n=0,event_valid=0;reg [1:0] target=0;
    wire arrived;wire [1:0] tone;
    integer count=0;reg [1:0] last_tone=3;reg last_arrived=0;
    posture_timbre_cdc dut(.src_clk(src),.src_rst_n(rst_n),.src_event(event_valid),.src_timbre(target),
        .dst_clk(dst),.dst_rst_n(rst_n),.dst_event(arrived),.dst_timbre(tone));
    always @(posedge dst)begin
        if(!rst_n)last_arrived<=0;
        else begin
            if(arrived)begin
                if(last_arrived || tone>1)$fatal(1,"FAIL: duplicated/torn CDC event");
                count=count+1;last_tone=tone;
            end
            last_arrived<=arrived;
        end
    end
    task send(input [1:0] value);
        @(negedge src);target=value;event_valid=1;@(negedge src);event_valid=0;
    endtask
    integer old_count;
    initial begin
        repeat(5)@(negedge src);rst_n=1;
        send(0);send(1);send(0);send(1);
        repeat(70)@(negedge src);
        if(count<2 || last_tone!=1)$fatal(1,"FAIL: held/coalesced latest CDC target");
        old_count=count;repeat(30)@(negedge dst);if(count!=old_count)$fatal(1,"FAIL: unsolicited replay");
        send(0);rst_n=0;repeat(8)@(negedge src);rst_n=1;
        repeat(20)@(negedge src);old_count=count;send(1);repeat(40)@(negedge src);
        if(count!=old_count+1 || last_tone!=1)$fatal(1,"FAIL: common-reset recovery");
        $display("PASS: asynchronous held enum/one-edge delivery/latest coalescing/no replay/common reset, %0d delivered",count);$finish;
    end
    initial begin #100000;$fatal(1,"FAIL: CDC watchdog");end
endmodule
