`timescale 1ns/1ps
module tb_karplus_strong;
    GSR GSR(.GSRI(1'b1));
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,strike=0;
    reg [31:0] inc[0:3];
    wire signed [27:0] pcm[0:3];
    wire [3:0] busy;
    integer f,n,k,u;
    integer updates[0:31];
    reg [63:0] energy[0:31];
    integer elapsed=0,max_elapsed=0;
    genvar v;
    generate for(v=0;v<4;v=v+1)begin:voices
        karplus_strong_voice #(.SEED(32'h12345678+(v==1 ? 0 : v)*7919)) dut(
            .clk(clk),.rst_n(rst_n),.context_index(2'd0),.start(start),.strike(strike),.enabled(1'b1),
            .sustain(v==1),.harmony(v==2),.increment(inc[v]),
            .harmony_increment(32'd58992947),.value(pcm[v]),.busy(busy[v]));
    end endgenerate
    genvar lane;
    generate for(v=0;v<4;v=v+1)begin:proof_voices
        for(lane=0;lane<2;lane=lane+1)begin:proof_lanes
            wire [1:0] selected=voices[v].dut.strings[lane].lane.current_slot;
            wire [9:0] base=voices[v].dut.strings[lane].lane.current_base;
            wire [8:0] capacity=voices[v].dut.strings[lane].lane.current_capacity;
            wire signed [17:0] wd=voices[v].dut.write_data[lane];
            always @(posedge clk)if(rst_n && voices[v].dut.write_enable[lane])begin
                if(voices[v].dut.address[lane]<base || voices[v].dut.address[lane]>=base+capacity)
                    $fatal(1,"model RAM region overlap");
                if(!voices[v].dut.strings[lane].lane.run_frame)$fatal(1,"unexpected muted model");
                updates[v*8+selected*2+lane]=updates[v*8+selected*2+lane]+1;
                energy[v*8+selected*2+lane]=energy[v*8+selected*2+lane]+(wd<0 ? -wd : wd);
            end
        end
    end endgenerate
    always @(negedge clk)begin
        if(start)elapsed=0;
        else if(busy!=0)elapsed=elapsed+1;
        if(elapsed>max_elapsed)max_elapsed=elapsed;
    end
    initial begin
        for(u=0;u<32;u=u+1)begin updates[u]=0;energy[u]=0;end
        inc[0]=32'd13138340; inc[1]=32'd13138340;
        inc[2]=32'd39394906; inc[3]=32'd70152776;
        f=$fopen("ks_pcm.txt","w");
        repeat(4)@(negedge clk);rst_n=1;
        wait(busy==0);@(negedge clk);max_elapsed=0;elapsed=0;
        for(n=0;n<144000;n=n+1) begin
            @(negedge clk);start=1;strike=n==0;
            // Slide, re-strike and reset mid-tail exercise initialized-memory masking.
            if(n>=48000 && n<49000) inc[3]=70152776+(n-48000)*4000;
            if(n==72000)strike=1;
            @(negedge clk);start=0;
            repeat(210)@(negedge clk);
            if(busy!==0)$fatal(1,"deadline");
            for(k=0;k<4;k=k+1) if(^pcm[k]===1'bx)$fatal(1,"unknown audio voice %0d sample %0d",k,n);
            $fwrite(f,"%0d %0d %0d %0d\n",pcm[0],pcm[1],pcm[2],pcm[3]);
        end
        for(u=0;u<32;u=u+1)begin
            if(updates[u]!=144000 || energy[u]==0)$fatal(1,"model state %0d not serviced independently",u);
        end
        if(max_elapsed>212)$fatal(1,"frame latency %0d",max_elapsed);
        $display("PASS: all32 regions independent, each144000 updates/nonzero energy; maximum busy=%0d clocks",max_elapsed);
        $fclose(f);$display("PASS: 4 parallel voices, 32 string states / 8 pipelines, 144000 frames, <=212 clocks/frame");$finish;
    end
endmodule
