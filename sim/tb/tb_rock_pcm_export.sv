`timescale 1ns/1ps
// Actual four-voice FULL source/effects/PCM16 pipeline, real 256-clock budget.
module tb_rock_pcm_export;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    reg [3:0] on=0,off=0;
    reg [127:0] inc={32'd17537826,32'd35075651,32'd29494568,32'd23409859};
    wire tick,valid;
    wire [95:0] pcm;
    wire [3:0] miss;
    wire [8:0] bright,rock;
    four_voice_piano_audio_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1)) source(
        .clk_audio_ref(clk),.rst_n(rst_n),.note_on(on),.note_off(off),
        .velocity_level(8'haa),.phase_inc(inc),.timbre_select(1'b0),.rock_select(1'b1),
        .sustain_enable(1'b0),.harmony_enable(1'b0),.sample_tick(tick),.sample_valid(valid),
        .voice_active(),.voice_pcm(pcm),.voice_profile(),.deadline_miss(miss),
        .timbre_blend(bright),.rock_blend(rock),.timbre_busy());
    reg signed [27:0] lsum,rsum,value;
    integer v;
    always @*begin
        lsum=0;rsum=0;
        for(v=0;v<4;v=v+1)begin
            value=$signed({{4{pcm[v*24+23]}},pcm[v*24+:24]});
            case(v)
                0:begin lsum=lsum+(value>>>1)+(value>>>3);rsum=rsum+(value>>>1)+(value>>>2);end
                1:begin lsum=lsum+(value>>>1)+(value>>>3)+(value>>>5);rsum=rsum+(value>>>1)+(value>>>3)+(value>>>4)+(value>>>5);end
                2:begin lsum=lsum+(value>>>1)+(value>>>3)+(value>>>4)+(value>>>5);rsum=rsum+(value>>>1)+(value>>>3)+(value>>>5);end
                3:begin lsum=lsum+(value>>>1)+(value>>>2);rsum=rsum+(value>>>1)+(value>>>3);end
            endcase
        end
    end
    integer files[0:1],frames[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin : variant
        wire fx_valid,left_valid,right_valid;
        wire signed [23:0] fx_l,fx_r;
        wire signed [15:0] l,r;
        piano_stereo_effects effects(
            .clk(clk),.rst_n(rst_n),.sample_valid_in(valid),.left_in(lsum[24:1]),.right_in(rsum[24:1]),
            .drive_level(2'd2),.timbre_blend(bright),.chorus_enable(1'b0),.room_enable(g==1),
            .sample_valid(fx_valid),.left_out(fx_l),.right_out(fx_r),
            .chorus_blend(),.reverb_blend(),.chorus_busy(),.reverb_busy());
        pcm24_to_16 left(.clk(clk),.rst_n(rst_n),.pcm_valid(fx_valid),.pcm_in(fx_l),.sample_valid(left_valid),.sample_out(l));
        pcm24_to_16 right(.clk(clk),.rst_n(rst_n),.pcm_valid(fx_valid),.pcm_in(fx_r),.sample_valid(right_valid),.sample_out(r));
        always @(posedge clk)begin
            #1;
            if(rst_n&&left_valid)begin
                if(!right_valid||miss||$isunknown({l,r})||l===16'h7fff||l===16'h8000||r===16'h7fff||r===16'h8000)
                    $fatal(1,"FAIL: rock preview cadence/data/headroom");
                $fwrite(files[g],"%04h %04h\n",l,r);frames[g]=frames[g]+1;
            end
        end
    end endgenerate
    integer n;
    initial begin
        files[0]=$fopen("rock_dry_pcm16.txt","w");files[1]=$fopen("rock_room_pcm16.txt","w");
        frames[0]=0;frames[1]=0;
        if(!files[0]||!files[1])$fatal(1,"FAIL: rock preview open");
        repeat(8)@(negedge clk);rst_n=1;
        for(n=0;n<528000;n=n+1)begin
            @(negedge tick);@(negedge clk);
            on=0;off=0;
            case(n)
                // No note-off: export the complete natural decay of each
                // strike, with enough spacing to hear the longer dry tail.
                7200:on=1;
                79200:on=2;
                151200:on=4;
                232800:on=7;
                319200:on=7;
                405600:on=15;
            endcase
        end
        wait(frames[0]==528000&&frames[1]==528000);
        $fclose(files[0]);$fclose(files[1]);
        $display("PASS: 528000 real-budget extended-wah PCM16 frames, dry/room; complete natural tails for C4 E4 G4, twice triad, G3 C4 E4 G4; no clipping, unknown data or deadline miss");
        $finish;
    end
    initial begin #1600000000;$fatal(1,"FAIL: rock export timeout");end
endmodule
