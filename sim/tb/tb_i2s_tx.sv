`timescale 1ns/1ps
// Receiver/scoreboard use only pins and reference clocks, not DUT state.
module tb_i2s_tx;
    reg clk=0; always #40.690104 clk=~clk;
    reg rst_n=0, valid=0;
    reg [15:0] left=0,right=0;
    wire bclk,ws,data,pb,pl,pd;
    i2s_tx dut(.clk_audio_ref(clk),.rst_n(rst_n),.sample_valid(valid),
        .sample_left(left),.sample_right(right),.i2s_bclk(bclk),.i2s_ws(ws),.i2s_data(data));
    pt8211_tx #(.REF_DIV(4)) legacy(.clk_audio_ref(clk),.rst_n(rst_n),.sample_valid(valid),
        .sample_left(left),.sample_right(right),.dac_bclk(pb),.dac_lrck(pl),.dac_din(pd));
    reg [31:0] expected[0:1023];
    reg [31:0] held=0,pending=0;
    reg pending_valid=0;
    integer clocks=0,commits=0,inputs=0,i2s_frames=0,pt_frames=0;
    integer total_i2s=0,total_pt=0,edge_checks=0;
    always @(posedge clk) begin
        if(!rst_n)begin
            clocks=0;commits=0;inputs=0;held=0;pending=0;pending_valid=0;expected[0]=0;
        end else begin
            clocks++;
            // Independent frame model. Coincident valid is accepted now;
            // otherwise consume the latest pending pair exactly once.
            if(clocks%256==0)begin
                if(valid)held={left,right};else if(pending_valid)held=pending;
                pending_valid=0;commits++;expected[commits]=held;
            end else if(valid)begin pending={left,right};pending_valid=1;end
            if(valid)inputs++;
        end
    end
    reg locked=0,last_ws=1,channel=0;
    reg [31:0] rx=0,left_word=0;
    integer bits=0,last_rise=0;
    always @(negedge rst_n)begin
        locked=0;last_ws=1;channel=0;rx=0;left_word=0;
        bits=0;last_rise=0;i2s_frames=0;pt_frames=0;
    end
    always @(posedge bclk) begin
        #1;
        if(rst_n)begin
            if(last_rise && clocks-last_rise!=4)$fatal(1,"FAIL: BCLK period");
            last_rise=clocks;
            if(locked)begin
                rx={rx[30:0],data};bits++;
                if(bits==32)begin
                    if(rx[15:0]!==0)$fatal(1,"FAIL: nonzero 16-bit padding %h",rx);
                    if(!channel)left_word=rx;
                    else begin
                        if({left_word[31:16],rx[31:16]}!==expected[i2s_frames])
                            $fatal(1,"FAIL: I2S pair %0d %h %h expected %h",i2s_frames,left_word,rx,expected[i2s_frames]);
                        i2s_frames++;total_i2s++;
                    end
                end
            end
            // The WS-change bit is the preceding channel's LAST bit.
            // The NEXT rising edge must be the new channel's MSB.
            if(ws!==last_ws)begin
                if(locked && bits!=32)$fatal(1,"FAIL: WS changed after %0d bits",bits);
                locked=1;channel=ws;bits=0;rx=0;last_ws=ws;
            end else if(locked && bits>=32)$fatal(1,"FAIL: WS did not change");
        end
    end
    reg [31:0] pt_rx=0;integer pt_bits=0;
    always @(negedge rst_n)begin pt_rx=0;pt_bits=0;end
    always @(posedge pb)begin
        #1;
        if(rst_n)begin
            if(pl!==(pt_bits>=16))$fatal(1,"FAIL: PT8211 channel");
            pt_rx={pt_rx[30:0],pd};pt_bits++;
            if(pt_bits==32)begin
                if(pt_rx!==expected[pt_frames])$fatal(1,"FAIL: PT8211 pair");
                pt_frames++;total_pt++;pt_bits=0;
            end
        end
    end
    // Pin changes must follow falling BCLK and never coincide with sampling.
    always @(ws or data)if(rst_n && $time>500)begin
        if(bclk!==0)$fatal(1,"FAIL: SD/WS changed with BCLK high");
        edge_checks++;
    end
    always @(posedge clk)begin
        #2;
        if(!rst_n && {bclk,ws,data}!==0)$fatal(1,"FAIL: reset not silent");
        if(rst_n && $isunknown({bclk,ws,data}))$fatal(1,"FAIL: unknown output");
    end
    integer epoch,n,offset,target;
    initial begin
        $dumpfile("i2s_tx.vcd");$dumpvars(0,tb_i2s_tx);
        repeat(8)@(negedge clk);
        for(epoch=0;epoch<3;epoch++)begin
            rst_n=1;
            for(n=0;n<100;n++)begin
                case(n%5)0:offset=1;1:offset=127;2:offset=128;3:offset=255;default:offset=256;endcase
                target=n*256+offset;
                while(clocks<target-1)@(negedge clk);
                // Distinct channels include signed limits, walking bits,
                // negatives, zeros and a different number every frame.
                left=n==0?16'h8000:n==1?16'h7fff:n<18?(16'h0001<<(n-2)):(16'h8001^(n*137));
                right=n==0?16'h7fff:n==1?16'h8000:(16'h0100+(n*211));
                valid=1;@(negedge clk);valid=0;
            end
            wait(i2s_frames>=101);
            if(inputs!=100 || pt_frames!=i2s_frames)$fatal(1,"FAIL: count/alignment");
            // Missing samples deliberately hold the last pair, on BOTH DACs.
            repeat(512)@(negedge clk);
            // Reset during a channel; new epoch must discard both old pairs.
            repeat(37)@(negedge clk);rst_n=0;valid=0;
            repeat(8)@(negedge clk);
        end
        if(total_i2s<300 || total_pt<300 || edge_checks<1000)$fatal(1,"FAIL: insufficient coverage");
        $display("PASS: I2S 32-bit slots/16-bit MSB-first/one-bit WS delay, stereo %0d pairs, PT %0d pairs, 100 regular inputs per reset epoch, coincident boundary, jitter, hold, mid-slot reset",total_i2s,total_pt);
        $finish;
    end
    initial begin #12000000;$fatal(1,"FAIL: I2S timeout");end
endmodule
