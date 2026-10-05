`timescale 1ns/1ps
module tb_piano_stereo_chorus;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,enable=0;
    reg signed [23:0] l=0,r=0;
    wire valid,busy;
    wire signed [23:0] out_l,out_r;
    wire [8:0] blend;
    piano_stereo_chorus #(.LFO_INCREMENT(32'd16777216)) dut(
        .clk(clk),.rst_n(rst_n),.sample_valid_in(ce),.left_in(l),.right_in(r),
        .chorus_enable(enable),.sample_valid(valid),.left_out(out_l),.right_out(out_r),
        .effect_blend(blend),.effect_busy(busy));
    integer ml[0:2047],mr[0:2047];
    integer ptr=0,fill=0,bl=0,j;
    reg [31:0] phase=0;
    integer triangle,dl,dr,al,ar,fl,fr,wet_weight;
    longint signed wl,wr,el,er;
    task step(input integer x,input integer y);
        triangle=phase[31]?65535-phase[30:15]:phase[30:15];
        dl=720*256+((triangle*384)>>8);
        dr=720*256+384*256-((triangle*384)>>8);
        al=(ptr-(dl>>8))&2047;ar=(ptr-(dr>>8))&2047;fl=dl&255;fr=dr&255;
        wl=fill>=1105?ml[al]*(256-fl)+ml[(al-1)&2047]*fl:0;
        wr=fill>=1105?mr[ar]*(256-fr)+mr[(ar-1)&2047]*fr:0;
        wet_weight=bl>>2;
        el=(longint'(x)*(256-wet_weight)+wl*wet_weight)>>>8;
        er=(longint'(y)*(256-wet_weight)+wr*wet_weight)>>>8;
        ml[ptr]=x>>>8;mr[ptr]=y>>>8;ptr=(ptr+1)&2047;
        if(fill<2048)fill=fill+1;
        if(enable&&bl<256)bl=bl+1;else if(!enable&&bl>0)bl=bl-1;
        phase=phase+32'd16777216;
        @(negedge clk);l=x;r=y;ce=1;@(negedge clk);ce=0;
        wait(valid);#1;
        if($isunknown({out_l,out_r})||out_l!==el[23:0]||out_r!==er[23:0]||blend!=bl)
            $fatal(1,"FAIL: stereo chorus step %0d actual=%d/%d expected=%d/%d",j,out_l,out_r,el,er);
        repeat(3)@(negedge clk);
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(j=0;j<3200;j=j+1)begin
            enable=(j>=800&&j<2400);
            step((j*7919)%1000000-500000,(j*113)%12000000-6000000);
        end
        @(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;
        ptr=0;fill=0;bl=0;phase=0;enable=1;
        for(j=0;j<1400;j=j+1)step(0,0);
        $display("PASS: 4600 exact stereo chorus samples; 15..23ms fractional delays, opposite LFOs, signed interpolation, wrap, dry bypass and reset with dirty RAM");$finish;
    end
endmodule
