`timescale 1ns/1ps
module tb_ks_integration;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0;
    reg [3:0] on=0,off=0,force_release=0;
    reg [8:0] timbre=0,rock=0;
    reg [31:0] increment[0:3];
    wire [3:0] valid,old_valid,miss,old_miss;
    wire signed [23:0] pcm[0:3],old_pcm[0:3];
    integer n,k,changes=0,unchanged=0,f;
    GSR GSR(.GSRI(1'b1));
    genvar v;
    generate for(v=0;v<4;v=v+1)begin:voices
        piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) dut(
            .ks_external_value(28'd0),.ks_external_busy(1'b0),
            .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on[v]),.note_off(off[v]),.velocity_level(v[1:0]),
            .phase_inc(increment[v]),.timbre_blend(timbre),.rock_blend(rock),.sustain_enable(v==1),
            .harmony_enable(v>=2),.force_release(force_release[v]),.sample_valid(valid[v]),.pcm_out(pcm[v]),
            .active(),.busy(),.deadline_miss(miss[v]),.profile());
        legacy_piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) old(
            .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on[v]),.note_off(off[v]),.velocity_level(v[1:0]),
            .phase_inc(increment[v]),.timbre_blend(timbre),.rock_blend(rock),.sustain_enable(v==1),
            .harmony_enable(v>=2),.force_release(force_release[v]),.sample_valid(old_valid[v]),.pcm_out(old_pcm[v]),
            .active(),.busy(),.deadline_miss(old_miss[v]),.profile());
    end endgenerate
    initial begin
        increment[0]=29493691;increment[1]=39370534;increment[2]=13138340;increment[3]=70152776;
        f=$fopen("integrated_pcm.txt","w");repeat(5)@(negedge clk);rst_n=1;
        for(n=0;n<18000;n=n+1)begin
            @(negedge clk);ce=1;for(k=0;k<4;k=k+1)begin
                on[k]=(n==k*31 || n==4000+k*31 || n==8000+k*31 || n==12000+k*31);
                off[k]=(n==2000+k*31 || n==6000+k*31 || n==14000+k*31);
                force_release[k]=n==17000+k*31;
            end
            if(n==4000)rock=256;
            if(n==8000)begin rock=0;timbre=256;end
            if(n>=10000 && n<11000)increment[3]=70152776+(n-10000)*3000;
            @(negedge clk);ce=0;
            repeat(254)begin
                @(negedge clk);
                if(valid!==old_valid)$fatal(1,"latency changed");
                if(miss!==0 || old_miss!==0)$fatal(1,"deadline");
                if(valid==15)for(k=0;k<4;k=k+1)begin
                    if(^pcm[k]===1'bx)$fatal(1,"unknown PCM");
                    if(n<8000)unchanged=unchanged+1;
                    if(n<8000 && pcm[k]!==old_pcm[k])$fatal(1,"piano/wah changed n=%0d voice=%0d",n,k);
                    if(n>=8000 && pcm[k]!==old_pcm[k])changes=changes+1;
                end
            end
            $fwrite(f,"%0d %0d %0d %0d\n",pcm[0],pcm[1],pcm[2],pcm[3]);
        end
        if(unchanged!=32000)$fatal(1,"missing comparison samples");
        if(changes<30000)$fatal(1,"KS not connected");
        $fclose(f);$display("PASS: 32000 unchanged piano/wah PCM, 40000 bright PCM, four velocities/harmony/sustain/slide/release, no deadline misses");$finish;
    end
endmodule

