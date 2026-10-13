`timescale 1ns/1ps
// Accepted recorded-residual engine vs procedural engine, identical full board
// controls / 4 x 32 modes / effects / 48 kHz cadence / 256-clock budget.
module tb_procedural_piano_ab;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable=0;
    reg [3:0] pluck=0;
    reg [15:0] frets=0;
    reg [7:0] velocity=0;
    reg bright=0,rock=0,chorus=0,sustain=0,room=0;
    wire [1:0] tick,mix_valid;
    wire [7:0] active;
    wire [191:0] voices;
    legacy_four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) old (
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(velocity),.timbre_select(bright),.rock_select(rock),
        .chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(1'b0),.reverb_enable(room),
        .sample_tick(tick[0]),.pcm_mix_valid(mix_valid[0]),.pcm_mix(),.voice_active(active[3:0]),
        .voice_pcm(voices[95:0]),.dac_bclk(),.dac_lrck(),.dac_din(),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid());
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) dut (
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(velocity),.timbre_select(bright),.rock_select(rock),
        .chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(1'b0),.reverb_enable(room),
        .sample_tick(tick[1]),.pcm_mix_valid(mix_valid[1]),.pcm_mix(),.voice_active(active[7:4]),
        .voice_pcm(voices[191:96]),.dac_bclk(),.dac_lrck(),.dac_din(),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid());
    integer frames=0,f0,f1,body_checks=0,alternate_checks=0,changed=0,four_seen=0;
    integer seed_checks=0;
    reg recording=0;
    genvar g;
    generate for(g=0;g<4;g=g+1)begin : verify
        wire [16:0] age=dut.g_piano.u_core.voice[g].u_voice.frame_age;
        wire [8:0] b=dut.g_piano.u_core.voice[g].u_voice.frame_timbre;
        wire [8:0] r=dut.g_piano.u_core.voice[g].u_voice.frame_rock;
        always @(posedge clk)begin
            #1;
            if(rst_n && dut.voice_sample_valid)begin
                if(age>=2048)begin
                    if(voices[g*24+:24]!==voices[96+g*24+:24])
                        $fatal(1,"FAIL: changed accepted modal body voice %0d age %0d",g,age);
                    body_checks=body_checks+1;
                end
                if((b==256 || r==256) && frames>110000)begin
                    if(voices[g*24+:24]!==voices[96+g*24+:24])
                        $fatal(1,"FAIL: changed bright/wah arithmetic voice %0d",g);
                    alternate_checks=alternate_checks+1;
                end
            end
        end
    end endgenerate
    always @(posedge clk)begin
        #2;
        if(rst_n)begin
            if(tick[0]!==tick[1] || mix_valid[0]!==mix_valid[1] || active[3:0]!==active[7:4] ||
               dut.deadline_miss!=0 || old.deadline_miss!=0)
                $fatal(1,"FAIL: A/B cadence/lifecycle/deadline");
            if(recording && dut.pcm16_left_valid)begin
                if(!old.pcm16_left_valid || $isunknown({dut.pcm16_left_out,dut.pcm16_right_out}))
                    $fatal(1,"FAIL: A/B output cadence/unknown");
                $fwrite(f0,"%04h %04h\n",old.pcm16_left_out,old.pcm16_right_out);
                $fwrite(f1,"%04h %04h\n",dut.pcm16_left_out,dut.pcm16_right_out);
                frames=frames+1;
                if(active[7:4]==15)four_seen=1;
                if(voices[95:0]!=voices[191:96])changed=changed+1;
                if(dut.pcm16_left_out==16'sh7fff || dut.pcm16_left_out==16'sh8000 ||
                   dut.pcm16_right_out==16'sh7fff || dut.pcm16_right_out==16'sh8000)
                    $fatal(1,"FAIL: A/B clipping");
            end
        end
    end
    task select(input [15:0] f);
        @(negedge clk);frets=f;stable=1;
        @(negedge clk);stable=0;
    endtask
    task launch(input [3:0] p);
        @(negedge clk);pluck=p;
        @(negedge clk);pluck=0;
    endtask
    integer n;
    initial begin
        f0=$fopen("procedural_ab_legacy_pcm16.txt","w");
        f1=$fopen("procedural_ab_new_pcm16.txt","w");
        if(!f0||!f1)$fatal(1,"FAIL: A/B file open");
        repeat(8)@(negedge clk);rst_n=1;
        select(16'h0553);repeat(512)@(negedge clk);recording=1;
        for(n=0;n<3;n=n+1)begin
            if(n!=0)begin
                // Isolate the three listening notes; both engines and their
                // effects reset together. The final polyphonic section does
                // retain normal fret release and overlapping natural decays.
                @(negedge clk);rst_n=0;repeat(8)@(negedge clk);rst_n=1;
                select(16'h0553);repeat(512)@(negedge clk);
            end
            velocity=n*8'h55;launch(4'b0100>>n);wait(frames>=(n+1)*24000);
        end
        velocity=8'hff;select(16'h5553);launch(15);
        wait(frames>=86000);select(0);
        wait(frames>=90000);chorus=1;sustain=1;room=1;
        wait(frames>=92000);launch(15);
        wait(frames>=92400);launch(15);
        wait(frames>=102000);bright=1;
        wait(frames>=110000);launch(15);
        wait(frames>=116000);rock=1;
        wait(frames>=124000);launch(15);
        wait(frames>=136000);recording=0;
        if(!four_seen || changed<5000 || body_checks<100000 || alternate_checks<50000)
            $fatal(1,"FAIL: incomplete A/B coverage %0d/%0d/%0d",changed,body_checks,alternate_checks);
        if(dut.g_piano.u_core.voice[0].u_voice.procedural_hammer.u_hammer.random_state==
           dut.g_piano.u_core.voice[1].u_voice.procedural_hammer.u_hammer.random_state)
            $fatal(1,"FAIL: correlated voice seeds");
        $fclose(f0);$fclose(f1);
        $display("PASS: 136000 full-chain PCM16 stereo A/B frames; four voices, four velocities, retrigger, open release, sustain/chorus/room; no clipping or deadline; %0d body and %0d bright/wah samples EXACTLY unchanged",body_checks,alternate_checks);
        $finish;
    end
    initial begin #360000000;$fatal(1,"FAIL: procedural A/B timeout");end
endmodule
