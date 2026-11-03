`timescale 1ns/1ps
// One physical-style C4 open-string pluck, same PCM24 -> effects -> PCM16
// pipeline as the board. All variants share input and a real 256-clock budget.
module tb_full_effects_pcm_export;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0;
    wire [7:0] voice_valid;
    wire [191:0] voice_pcm;
    wire [15:0] pcm16_valid;
    wire [511:0] stereo_pcm16;
    integer files[0:15],counts[0:15];
    wire [7:0] bad;
    genvar g,k;
    generate for(g=0;g<8;g=g+1)begin : voice
        localparam integer BRIGHT=(g%4)>=2;
        localparam integer SUSTAIN=g%2;
        if(g<4)begin : old
            fxv1_piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1)) u_voice(
                .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(1'b0),
                .phase_inc(32'd23409859),.velocity_level(2'd2),.timbre_blend(BRIGHT?9'd256:9'd0),
                .sustain_enable(SUSTAIN!=0),.harmony_enable(1'b0),.sample_valid(voice_valid[g]),
                .pcm_out(voice_pcm[g*24+:24]),.active(),.busy(),.deadline_miss(bad[g]),.profile());
        end else begin : updated
            piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1)) u_voice(
        .rock_blend(9'd0),
                .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(1'b0),
                .phase_inc(32'd23409859),.velocity_level(2'd2),.timbre_blend(BRIGHT?9'd256:9'd0),
                .sustain_enable(SUSTAIN!=0),.harmony_enable(1'b0),.sample_valid(voice_valid[g]),
                .pcm_out(voice_pcm[g*24+:24]),.active(),.busy(),.deadline_miss(bad[g]),.profile());
        end
    end
    for(k=0;k<16;k=k+1)begin : output_variant
        localparam integer EDITION=k/8,TONE=(k%8)/4,FX=k%4;
        localparam integer SOURCE=EDITION*4+TONE*2+(FX==3);
        wire signed [27:0] value=$signed({{4{voice_pcm[SOURCE*24+23]}},voice_pcm[SOURCE*24+:24]});
        wire signed [27:0] mix_l=(value>>>1)+(value>>>3)+(value>>>4)+(value>>>5);
        wire signed [27:0] mix_r=(value>>>1)+(value>>>3)+(value>>>5);
        wire valid;
        wire signed [23:0] l,r;
        if(EDITION==0)begin : old
            fxv1_piano_stereo_effects u_effects(
                .clk(clk),.rst_n(rst_n),.sample_valid_in(voice_valid[SOURCE]),
                .left_in(mix_l[24:1]),.right_in(mix_r[24:1]),.drive_level(2'd2),
                .timbre_blend(TONE?9'd256:9'd0),.chorus_enable(FX==1),.room_enable(FX==2),
                .sample_valid(valid),.left_out(l),.right_out(r),.chorus_blend(),.reverb_blend(),
                .chorus_busy(),.reverb_busy());
        end else begin : updated
            piano_stereo_effects u_effects(
                .clk(clk),.rst_n(rst_n),.sample_valid_in(voice_valid[SOURCE]),
                .left_in(mix_l[24:1]),.right_in(mix_r[24:1]),.drive_level(2'd2),
                .timbre_blend(TONE?9'd256:9'd0),.chorus_enable(FX==1),.room_enable(FX==2),
                .sample_valid(valid),.left_out(l),.right_out(r),.chorus_blend(),.reverb_blend(),
                .chorus_busy(),.reverb_busy());
        end
        wire right_valid;
        pcm24_to_16 u_left(.clk(clk),.rst_n(rst_n),.pcm_valid(valid),.pcm_in(l),
            .sample_valid(pcm16_valid[k]),.sample_out(stereo_pcm16[k*32+:16]));
        pcm24_to_16 u_right(.clk(clk),.rst_n(rst_n),.pcm_valid(valid),.pcm_in(r),
            .sample_valid(right_valid),.sample_out(stereo_pcm16[k*32+16+:16]));
        always @(posedge clk)begin
            #1;
            if(rst_n && pcm16_valid[k])begin
                if(!right_valid||bad||$isunknown(stereo_pcm16[k*32+:32]))$fatal(1,"FAIL: preview cadence/unknown");
                if(stereo_pcm16[k*32+:16]===16'h7fff||stereo_pcm16[k*32+:16]===16'h8000||
                   stereo_pcm16[k*32+16+:16]===16'h7fff||stereo_pcm16[k*32+16+:16]===16'h8000)
                    $fatal(1,"FAIL: preview clipping");
                $fwrite(files[k],"%04h %04h\n",stereo_pcm16[k*32+:16],stereo_pcm16[k*32+16+:16]);
                counts[k]=counts[k]+1;
            end
        end
    end endgenerate
    integer i,n;
    initial begin
        for(i=0;i<16;i=i+1)begin
            files[i]=$fopen($sformatf("full_effects_%0d_pcm16.txt",i),"w");counts[i]=0;
            if(!files[i])$fatal(1,"FAIL: preview open");
        end
        repeat(8)@(negedge clk);rst_n=1;
        for(n=0;n<192000;n=n+1)begin
            @(negedge clk);ce=1;on=n==7200;
            @(negedge clk);ce=0;on=0;
            repeat(254)@(negedge clk);
        end
        for(i=0;i<16;i=i+1)begin
            if(counts[i]!=192000)$fatal(1,"FAIL: variant %0d frame count %0d",i,counts[i]);
            $fclose(files[i]);
        end
        $display("PASS: 16 actual RTL stereo PCM16 exports, 192000 samples each; identical open C4 pluck; old/new piano and bright dry/chorus/room/sustain; no clipping, unknown data or deadlines");
        $finish;
    end
endmodule
