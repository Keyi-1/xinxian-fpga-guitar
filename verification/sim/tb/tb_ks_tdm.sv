`timescale 1ns/1ps
module tb_ks_tdm;
    reg audio_clk=0;always #40.690104 audio_clk=~audio_clk;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;
    reg rst_n=0;
    reg [3:0] on=0,off=0,force_release=0;
    reg [127:0] inc;
    reg bright=0,rock=0,sustain=0,harmony=0;
    wire tick,valid,ref_valid;
    wire [95:0] pcm,ref_pcm;
    wire [3:0] miss,ref_miss;
    integer n,k,comparisons=0;
    time previous_edge;
    GSR GSR(.GSRI(1'b1));
    four_voice_piano_audio_core #(.KS_TDM_ENABLE(1),.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) dut(
        .clk_audio_ref(audio_clk),.clk_synth_ref(sys_clk),.rst_n(rst_n),.note_on(on),.note_off(off),.force_release(force_release),
        .velocity_level(8'he4),.phase_inc(inc),.timbre_select(bright),.rock_select(rock),.sustain_enable(sustain),.harmony_enable(harmony),
        .sample_tick(tick),.sample_valid(valid),.voice_pcm(pcm),.deadline_miss(miss),.voice_active(),.voice_profile(),.timbre_blend(),.rock_blend(),.timbre_busy());
    four_voice_piano_audio_core #(.KS_TDM_ENABLE(0),.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) reference(
        .clk_audio_ref(audio_clk),.clk_synth_ref(sys_clk),.rst_n(rst_n),.note_on(on),.note_off(off),.force_release(force_release),
        .velocity_level(8'he4),.phase_inc(inc),.timbre_select(bright),.rock_select(rock),.sustain_enable(sustain),.harmony_enable(harmony),
        .sample_tick(),.sample_valid(ref_valid),.voice_pcm(ref_pcm),.deadline_miss(ref_miss),.voice_active(),.voice_profile(),.timbre_blend(),.rock_blend(),.timbre_busy());
    always @(posedge dut.tdm_compute.compute_clk)if(dut.tdm_compute.locked)begin
        if(previous_edge!=0 && $time-previous_edge!=10)$fatal(1,"PLL is not 100 MHz");
        previous_edge=$time;
    end
    always @(negedge audio_clk)if(rst_n)begin
        if(miss!==0 || ref_miss!==0)$fatal(1,"TDM missed sample deadline");
        if(valid!==ref_valid)$fatal(1,"output latency changed");
        if(valid)begin
            if(pcm!==ref_pcm)$fatal(1,"TDM/parallel mismatch sample=%0d got=%h expected=%h",comparisons,pcm,ref_pcm);
            comparisons=comparisons+1;
        end
    end
    initial begin
        previous_edge=0;
        inc={32'd70152776,32'd13138340,32'd39370534,32'd29493691};
        // Let the actual vendor PLL lock before releasing the production reset.
        #200000;@(negedge audio_clk);rst_n=1;
        for(n=0;n<14000;n=n+1)begin
            @(posedge tick);@(negedge audio_clk);
            for(k=0;k<4;k=k+1)begin
                on[k]=(n==k*11 || n==3000+k*11 || n==7000+k*11 || n==10000+k*11);
                off[k]=(n==5000+k*11 || n==12000+k*11);
                force_release[k]=n==13500+k*11;
            end
            if(n==2000)bright=1;
            if(n==6000)begin sustain=1;harmony=1;end
            if(n==9000)rock=1;
            if(n==11000)begin rock=0;bright=0;sustain=0;end
            if(n>=4000 && n<4500)inc[127:96]=70152776+(n-4000)*1000;
        end
        if(comparisons<13990 || previous_edge==0)$fatal(1,"insufficient samples or PLL absent");
        $display("PASS: actual PLL100 MHz, TDM32 contexts vs parallel32 bit-exact %0d four-voice samples, CDC/timbre/sustain/harmony/slide/releases",comparisons*4);$finish;
    end
endmodule
