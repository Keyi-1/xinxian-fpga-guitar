`timescale 1ns/1ps
module tb_vibrato_audio_div15_preservation;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,bright=0,rock=0,chorus=0,sustain=0,harmony=0,reverb=0;
    reg [3:0] attack=0,release_mask=0,requests=0;
    reg [7:0] velocity=8'he4;
    reg [127:0] target={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
    wire [2:0] ticks,valid;
    wire [3:0] active[0:2];
    wire [95:0] voices[0:2];
    wire signed [23:0] pcm[0:2];
    wire [127:0] phase[0:2];
    wire [5:0] pins[0:2];
    GSR GSR(.GSRI(1'b1));
`define CONFIG .EXTERNAL_CONTROL_ENABLE(1),.I2S_ENABLE(1),.USE_PIANO(1),.CONTROL_PHASE_VALUE_BITS(27),.PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)
`define PORTS(n) .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(1'b0),.stable_fret_id(16'd0),.pluck_valid(4'd0), \
    .velocity_level(velocity),.timbre_select(bright),.rock_select(rock),.chorus_enable(chorus),.sustain_enable(sustain), \
    .harmony_enable(harmony),.reverb_enable(reverb),.sample_tick(ticks[n]),.pcm_mix_valid(valid[n]),.pcm_mix(pcm[n]), \
    .voice_active(active[n]),.voice_pcm(voices[n]),.display_phase_inc(phase[n]),.display_note_on(),.display_voice_sample_valid(), \
    .external_note_on(attack),.external_note_off(4'd0),.external_force_release(release_mask),.external_phase_inc(target), \
    .game_cue_enable(1'b0),.game_miss_event(1'b0),.control_pipeline_idle(),.control_timbre_busy(), \
    .dac_bclk(pins[n][0]),.dac_lrck(pins[n][1]),.dac_din(pins[n][2]),.i2s_bclk(pins[n][3]),.i2s_ws(pins[n][4]),.i2s_data(pins[n][5])
    four_string_board_audio_chain #(`CONFIG,.VIBRATO_ENABLE(1)) dut(`PORTS(0),.external_vibrato_enable(requests));
    vibrato_before_v6_four_string_board_audio_chain #(`CONFIG) frozen(`PORTS(1));
    vibrato_oracle_v6_four_string_board_audio_chain #(`CONFIG) oracle(`PORTS(2),.external_vibrato_enable(requests));
`undef PORTS
`undef CONFIG
    reg changed=0;
    integer frozen_samples=0,oracle_samples=0,different_samples=0,clocks=0;
    always @(posedge clk)if(rst_n)begin
        if(ticks[0] && phase[0]!==phase[2])$fatal(1,"FAIL: consumed vibrato phase differs from independent multiplier oracle");
        #1;
        clocks=clocks+1;
        if(ticks!=={3{ticks[0]}} || valid!=={3{valid[0]}})$fatal(1,"FAIL: sample/valid schedule changed");
        if(active[0]!==active[2] || voices[0]!==voices[2] || pcm[0]!==pcm[2] || pins[0]!==pins[2])
            $fatal(1,"FAIL: vibrato PCM or dual digital output oracle mismatch at clock %d",clocks);
        if(!changed && (active[0]!==active[1] || voices[0]!==voices[1] || pcm[0]!==pcm[1] || pins[0]!==pins[1]))
            $fatal(1,"FAIL: inactive vibrato changed frozen production audio");
        if(dut.g_piano.u_core.deadline_miss || dut.performance_vibrato.deadline_miss)
            $fatal(1,"FAIL: audio or modulation deadline");
        if(valid[0])begin
            oracle_samples=oracle_samples+1;
            if(!changed)frozen_samples=frozen_samples+1;
            else if(pcm[0]!==pcm[1])different_samples=different_samples+1;
        end
    end
    task wait_samples(input integer count);
        repeat(count)begin
            @(negedge clk);while(!ticks[0])@(negedge clk);
            @(negedge clk);
        end
    endtask
    task strike(input [3:0] mask);
        @(negedge clk);while(!ticks[0])@(negedge clk);
        attack=mask;@(negedge clk);attack=0;
    endtask
    integer tone;
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(tone=0;tone<3;tone=tone+1)begin
            bright=tone==1;rock=tone==2;chorus=tone!=0;sustain=tone==1;
            harmony=tone!=1;reverb=tone==2;
            strike(15);wait_samples(4096);
        end
        if(frozen_samples<12288)$fatal(1,"FAIL: frozen comparison coverage");
        changed=1;
        for(tone=0;tone<3;tone=tone+1)begin
            requests=0;bright=tone==1;rock=tone==2;chorus=tone!=0;sustain=tone==1;
            harmony=tone!=1;reverb=tone==2;
            strike(15);wait_samples(1024);requests=15;wait_samples(9216);
            requests[0]=0;target[31:0]=32'h0258a2f5;wait_samples(1000);
            target[31:0]=32'h01c20d2f;wait_samples(1000);
            strike(2);wait_samples(128);requests=0;
        end
        release_mask=15;wait_samples(1);release_mask=0;wait_samples(1600);
        if(different_samples<1000)$fatal(1,"FAIL: requested vibrato did not change audible PCM");
        $display("PASS: vibrato audio preservation frozen=%0d independent-oracle=%0d changed=%0d samples, three timbres/four velocities/all effects/slide/open/restrike/release, %0d PT8211/I2S clocks, no deadlines",frozen_samples,oracle_samples,different_samples,clocks);
        $finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: vibrato audio timeout");end
endmodule
