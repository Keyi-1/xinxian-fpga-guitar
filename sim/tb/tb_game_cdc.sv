`timescale 1ns/1ps
module tb_game_cdc;
    reg src_clk=0,dst_clk=0;always #7 src_clk=~src_clk;always #11 dst_clk=~dst_clk;
    reg rst_n=0,send=0,ack=0,request=0;reg [1:0] mode=0;
    wire busy,done,valid;wire [1:0] dst_mode;
    reg [31:0] sequence_number=0;
    wire [255:0] source_snapshot={8{sequence_number}};
    wire [255:0] snapshot;wire update;
    mode_command_cdc command(.src_clk(src_clk),.src_rst_n(rst_n),.src_send(send),.src_mode(mode),
        .src_busy(busy),.src_done(done),.dst_clk(dst_clk),.dst_rst_n(rst_n),
        .dst_valid(valid),.dst_mode(dst_mode),.dst_ack(ack));
    game_snapshot_cdc telemetry(.src_clk(src_clk),.src_rst_n(rst_n),.src_snapshot(source_snapshot),
        .dst_clk(dst_clk),.dst_rst_n(rst_n),.dst_request(request),.dst_snapshot(snapshot),.dst_update(update));
    always @(posedge src_clk)sequence_number<=sequence_number+1'b1;
    integer i,j,updates=0;
    always @(negedge dst_clk)if(update)begin
        if(snapshot!={8{snapshot[31:0]}})$fatal(1,"FAIL: torn telemetry word");
        updates=updates+1;
    end
    initial begin
        repeat(5)@(negedge src_clk);rst_n=1;
        for(i=0;i<100;i=i+1)begin
            @(negedge src_clk);mode=i%4;send=1;
            @(negedge src_clk);send=0;mode=(i+1)%4;
            wait(valid);if(dst_mode!=i%4)$fatal(1,"FAIL: held command data changed");
            repeat(7)@(negedge dst_clk);
            if(!busy || done)$fatal(1,"FAIL: premature command acknowledgement");
            ack=1;@(negedge dst_clk);ack=0;wait(done);
            @(negedge dst_clk);request=1;@(negedge dst_clk);request=0;
            wait(update);repeat(3)@(negedge src_clk);
        end
        repeat(5)@(negedge dst_clk);
        if(updates!=100)$fatal(1,"FAIL: lost/duplicated snapshots");
        $display("PASS: 100 asynchronous held commands and coherent 256-bit snapshots, delayed ACK");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: CDC watchdog");end
endmodule
