`timescale 1ns/1ps
// New transport trace only. Unchanged production P3 service/DPB/CDC.
module tb_p5_bridge_replay;
    GSR GSR(.GSRI(1'b1));
    localparam BIT=24;
    reg clk=0,ac=0,rst=0,rx=1,allowed=1;
    always #10 clk=~clk; always #14 ac=~ac;
    wire tx,locked,we,vr;wire [10:0] wa,va;
    wire [95:0] wd,vd,audio_word;wire [4:0] sv,av;wire [479:0] sd,ad;
    game_p3_service #(.UART_CLKS_PER_BIT(BIT)) dut(.clk(clk),.rst_n(rst),.audio_clk(ac),.audio_rst_n(rst),.rx(rx),.tx(tx),
        .audio_idle(1'b1),.menu_idle(allowed),.frame_begin(1'b1),.locked(locked),
        .write_enable(we),.write_address(wa),.write_data(wd),.verify_read(vr),.verify_address(va),.verify_data(vd),
        .system_valid(sv),.audio_valid(av),.system_data(sd),.audio_data(ad));
    reg ar=0;reg [10:0] aa=703;
    game_p3_score_bank bank(.audio_clk(ac),.audio_read(ar),.audio_address(aa),.audio_data(audio_word),
        .display_clk(clk),.display_read(vr),.display_address(va),.display_data(vd),
        .write_enable(we),.write_address(wa),.write_data(wd));
    integer rx_count=0,packets=0,writes=0;
    reg [7:0] received[0:4095];
    `include "game_p3_uart_host.vh"
    reg [7:0] requests[0:543],expected[0:16],allow[0:16];
    string dir;integer f,k,j,first,output_file;reg [31:0] check;reg [95:0] accepted;
    always @(posedge clk)if(we)writes=writes+1;
    initial begin
        if(!$value$plusargs("vectors=%s",dir))$fatal(1,"FAIL: vectors required");
        $readmemh({dir,"/requests.hex"},requests);$readmemh({dir,"/expected.hex"},expected);$readmemh({dir,"/allowed.hex"},allow);
        output_file=$fopen({dir,"/responses.hex"},"w");if(!output_file)$fatal(1,"FAIL: response output");
        repeat(8)@(negedge clk);rst=1;repeat(8)@(negedge clk);
        for(f=0;f<17;f=f+1)begin
            allowed=allow[f][0];repeat(8)@(negedge clk);first=rx_count;
            for(k=0;k<32;k=k+1)byte_send(requests[f*32+k]);
            wait(rx_count>=first+32);
            if(received[first]!==8'h58 || received[first+1]!==8'h47 || received[first+2]!==8'h33 || received[first+3]!==8'h21 ||
               received[first+4]!==3 || received[first+5]!==(requests[f*32+5]|8'h80) || received[first+10]!==expected[f])
                $fatal(1,"FAIL: RTL response frame%0d status%0d expected%0d",f,received[first+10],expected[f]);
            for(j=6;j<10;j=j+1)if(received[first+j]!==requests[f*32+j])$fatal(1,"FAIL: RTL session/sequence");
            check=32'hffffffff;for(k=4;k<28;k=k+1)check=crc_byte(check,received[first+k]);check=check^32'hffffffff;
            if({received[first+31],received[first+30],received[first+29],received[first+28]}!==check)$fatal(1,"FAIL: RTL ACK CRC");
            for(k=0;k<32;k=k+1)$fdisplay(output_file,"%02x",received[first+k]);
            if(f==5)begin
                if(!sv[4] || sv!==av || sd!==ad || sd[4*96+43+:12]!=2 || sd[4*96+55+:32]!=48000)
                    $fatal(1,"FAIL: actual readback/CDC publication");
                accepted=sd[4*96+:96];
            end
            if(f>5 && sd[4*96+:96]!==accepted)$fatal(1,"FAIL: failed replacement changed old descriptor");
            if(f==3 && writes!=1)$fatal(1,"FAIL: repeated DATA duplicated RAM write");
            packets=packets+1;repeat(BIT)@(negedge clk);
        end
        if(writes!=3 || locked)$fatal(1,"FAIL: write accounting/unlock");
        @(negedge ac);ar=1;@(posedge ac);#1;
        if(audio_word!=={16'hbeef,5'd0,2'd2,2'd0,7'd79,32'd12000,32'd0})$fatal(1,"FAIL: old actual DPB overwritten");
        $fclose(output_file);
        $display("PASS: 17 C-bridge UART traces, actual P3 RTL/DPB readback CRC/async atomic commit, duplicate DATA/COMMIT, BUSY/NO_SPACE/CRC replacement protection; accelerated UART, no real radio or new netlist");
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: replay watchdog");end
endmodule
