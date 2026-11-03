`timescale 1ns/1ps
module tb_jdy23_xg3;
    GSR GSR(.GSRI(1'b1));
    localparam BIT=5208;
    reg clk=0,ac=0,rst=0,rx=1;
    always #10 clk=~clk;
    always #40.690104 ac=~ac;
    wire tx,locked,we,verify_read;
    wire [10:0] wa,verify_address;
    wire [95:0] wd,verify_data,audio_data;
    wire [4:0] sv,av;
    wire [479:0] sd,ad;
    integer rx_count=0,packets=0,writes=0;
    reg [7:0] received[0:4095];
    game_p3_service #(.UART_CLKS_PER_BIT(BIT)) dut(
        .clk(clk),.rst_n(rst),.audio_clk(ac),.audio_rst_n(rst),.rx(rx),.tx(tx),
        .audio_idle(1'b1),.menu_idle(1'b1),.frame_begin(1'b1),.locked(locked),
        .write_enable(we),.write_address(wa),.write_data(wd),
        .verify_read(verify_read),.verify_address(verify_address),.verify_data(verify_data),
        .system_valid(sv),.audio_valid(av),.system_data(sd),.audio_data(ad));
    game_p3_score_bank bank(.audio_clk(ac),.audio_read(1'b0),.audio_address(11'd0),.audio_data(audio_data),
        .display_clk(clk),.display_read(verify_read),.display_address(verify_address),.display_data(verify_data),
        .write_enable(we),.write_address(wa),.write_data(wd));
    always @(posedge clk)if(we)writes=writes+1;
    `include "jdy23_uart_host.vh"
    reg [127:0] one,begin_payload;
    reg [31:0] song_crc;
    integer before_count;
    initial begin
        repeat(10)@(negedge clk);rst=1;
        one={16'd0,16'hbeef,8'd0,8'd2,8'd0,8'd79,32'd12000,32'd0};
        song_crc=crc_record(32'hffffffff,one)^32'hffffffff;
        begin_payload={32'd0,song_crc,32'd24000,16'd1,8'd1,8'd4};
        transact(1,17,0,0,0); // HELLO, 20+12 physical UART fragments.
        if(last_reply[31:8]!==24'h200502)$fatal(1,"FAIL: HELLO capability");
        transact(3,17,1,begin_payload,0);
        transact(4,17,2,one,0);before_count=writes;
        transact(4,17,2,one,0); // Exact retry must not write a second record.
        if(writes!=before_count)$fatal(1,"FAIL: duplicate DATA wrote twice");
        transact(5,17,3,0,0);wait(av[4]);
        transact(5,17,3,0,0); // Commit reply replay, no duplicate publish.
        transact(2,17,4,128'd4,0);
        if(!sv[4]||!av[4]||locked||writes!=1)$fatal(1,"FAIL: RAM commit/catalog");
        transact(2,17,5,128'd4,12,1); // Corrupted request must be rejected.
        $display("PASS: JDY-23 9600 20+12 stream -> actual XG3 service -> BSRAM readback CRC -> async publish; DATA/COMMIT retry");
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: XG3 watchdog");end
endmodule
