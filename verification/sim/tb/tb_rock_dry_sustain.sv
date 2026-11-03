`timescale 1ns/1ps
// Unreleased C4, physical sample budget and board voice-0 panning/effects/PCM16.
// Compare dry with sustain, with all oscillator and envelope state unforced.
module tb_rock_dry_sustain;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0;
    wire [1:0] valid,miss;
    wire [47:0] pcm;
    integer files[0:1],frames[0:1];
    reg signed [63:0] early[0:1],late[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin : variant
        piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1)) source(
            .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(1'b0),
            .phase_inc(32'd23409859),.velocity_level(2'd2),.timbre_blend(9'd0),.rock_blend(9'd256),
            .sustain_enable(g==1),.harmony_enable(1'b0),.sample_valid(valid[g]),
            .pcm_out(pcm[g*24+:24]),.active(),.busy(),.deadline_miss(miss[g]),.profile());
        wire signed [27:0] value=$signed({{4{pcm[g*24+23]}},pcm[g*24+:24]});
        wire signed [27:0] lsum=(value>>>1)+(value>>>3);
        wire signed [27:0] rsum=(value>>>1)+(value>>>2);
        wire fx_valid,l_valid,r_valid;
        wire signed [23:0] fx_l,fx_r;
        wire signed [15:0] l,r;
        piano_stereo_effects effects(
            .clk(clk),.rst_n(rst_n),.sample_valid_in(valid[g]),.left_in(lsum[24:1]),.right_in(rsum[24:1]),
            .drive_level(2'd2),.timbre_blend(9'd0),.chorus_enable(1'b0),.room_enable(1'b0),
            .sample_valid(fx_valid),.left_out(fx_l),.right_out(fx_r),
            .chorus_blend(),.reverb_blend(),.chorus_busy(),.reverb_busy());
        pcm24_to_16 left(.clk(clk),.rst_n(rst_n),.pcm_valid(fx_valid),.pcm_in(fx_l),.sample_valid(l_valid),.sample_out(l));
        pcm24_to_16 right(.clk(clk),.rst_n(rst_n),.pcm_valid(fx_valid),.pcm_in(fx_r),.sample_valid(r_valid),.sample_out(r));
        always @(posedge clk)begin
            #1;
            if(rst_n&&l_valid)begin
                if(!r_valid||miss||$isunknown({l,r})||l===16'h7fff||l===16'h8000||r===16'h7fff||r===16'h8000)
                    $fatal(1,"FAIL: dry/sustain cadence/data/headroom");
                $fwrite(files[g],"%04h %04h\n",l,r);
                if(frames[g]>=2400&&frames[g]<4800)early[g]=early[g]+$signed(l)*$signed(l)+$signed(r)*$signed(r);
                if(frames[g]>=48000&&frames[g]<50400)late[g]=late[g]+$signed(l)*$signed(l)+$signed(r)*$signed(r);
                if(g==1&&frames[g]<2048&&(l!==variant[0].l||r!==variant[0].r))
                    $fatal(1,"FAIL: sustain changed initial pick/phase");
                if(g==0&&frames[g]>=55700&&(l!==0||r!==0))$fatal(1,"FAIL: dry tail exceeds extended boundary");
                if(g==1&&frames[g]>=216500&&(l!==0||r!==0))$fatal(1,"FAIL: sustain tail restarts");
                frames[g]=frames[g]+1;
            end
        end
    end endgenerate
    integer n;
    initial begin
        files[0]=$fopen("rock_c4_dry_pcm16.txt","w");files[1]=$fopen("rock_c4_sustain_pcm16.txt","w");
        for(n=0;n<2;n=n+1)begin frames[n]=0;early[n]=0;late[n]=0;end
        if(!files[0]||!files[1])$fatal(1,"FAIL: decay export open");
        repeat(8)@(negedge clk);rst_n=1;
        for(n=0;n<240000;n=n+1)begin
            @(negedge clk);ce=1;on=n==0;
            @(negedge clk);ce=0;on=0;
            repeat(254)@(negedge clk);
        end
        wait(frames[0]==240000&&frames[1]==240000);
        if(early[0]==0||early[1]==0||late[0]*20>early[0]||late[1]<late[0]*8)
            $fatal(1,"FAIL: weak dry/sustain separation %0d %0d / %0d %0d",early[0],late[0],early[1],late[1]);
        $fclose(files[0]);$fclose(files[1]);
        $display("PASS: 240000 real-budget extended-wah C4 stereo frames per variant; same initial pick, dry zero after 1.161 s, sustain zero after 4.511 s, 1s dry energy < -13 dB, sustain > 8x dry; no forced state");
        $finish;
    end
endmodule
