`timescale 1ns/1ps
// Production audio child, physical matrix columns and registered ADC-event
// stimuli. The separate frozen synthesis chain receives an independent pitch
// scenario; no note, DDS, phase, audio or matrix state is forced.
module tail_audio_reference(input wire clk,sysclk,rst_n,input wire [31:0] contacts,
    input wire [3:0] pluck,input wire command_valid,input wire [1:0] command_mode,
    output wire [5:0] pins,output wire valid,ack,tick,switching,
    output wire [15:0] pcm,output wire [1:0] mode,output wire [3:0] rows);
    reg [7:0] columns;
    wire [23:0] pcm24;
    always @*begin
        columns=255;
        for(integer s=0;s<4;s=s+1)if(rows[s])columns=~contacts[s*8+:8];
    end
`ifdef TAIL_GATE
    rtlref_guitar_touch_game_audio
`else
    guitar_touch_game_audio
`endif
    #(.USE_P2(1),.WRITABLE(1)) u_audio(
        .clk(clk),.rst_n(rst_n),.command_valid(command_valid),.command_mode(command_mode),.command_ack(ack),
        .fret_col_in_n(columns),.command_slot(3'd0),.display_clk(sysclk),.display_read(1'b0),.display_address(11'd0),
        .display_data(),.timbre_load(),.timbre_code(),.overlay_valid(5'd0),.overlay_data(480'd0),
        .write_enable(1'b0),.write_address(11'd0),.write_data(96'd0),.storage_idle(),
        .fret_row_oe(rows),.fret_row_drive_n(),.adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),
        .timbre_select(1'b0),.rock_select(1'b0),.chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .dac_bclk(pins[0]),.dac_lrck(pins[1]),.dac_din(pins[2]),.i2s_bclk(pins[3]),.i2s_ws(pins[4]),.i2s_data(pins[5]),
        .visual_snapshot(),.game_snapshot(),.final_pcm_valid(valid),.final_pcm(pcm24),
        .posture_sample_tick(tick),.posture_performance(),.posture_pipeline_idle(),.posture_timbre_busy(),
        .posture_voice_active(),.posture_note_guard());
    assign pcm=pcm24[23:8];assign mode=u_audio.mode;assign switching=u_audio.switching;
    initial begin
        force u_audio.u_adc.pluck_valid=pluck;
        force u_audio.u_adc.velocity_level=8'haa;
        force u_audio.u_adc.capture_pending=4'd0;
    end
endmodule

module tb_tail_lock_audio;
    reg clk=0,sysclk=0;always #40.690104 clk=~clk;always #10 sysclk=~sysclk;
    reg rst_n=0,command_valid=0;
    reg [1:0] command_mode=0;
    reg [31:0] contacts=0;
    reg [3:0] pluck=0,allow_slide=15,expected_attack=0;
    wire [5:0] rpins;wire valid,ack,tick,switching;
    wire [1:0] mode;wire [3:0] rows;
    wire [15:0] pcm;
    reg [31:0] phase_rom[0:35];
    reg [127:0] expected_target={32'h00c879a3,32'h010b9a2b,32'h0151285d,32'h01c20d2f};
    wire oracle_valid,oracle_tick;wire [5:0] opins;
    wire signed [23:0] oracle_pcm;wire [3:0] oracle_active;
    integer step=0,samples=0,attacks=0,pcm_checks=0,release_counts[0:3];
    GSR GSR(.GSRI(1'b1));
    tail_audio_reference reference(.clk(clk),.sysclk(sysclk),.rst_n(rst_n),.contacts(contacts),.pluck(pluck),
        .command_valid(command_valid),.command_mode(command_mode),.pins(rpins),.valid(valid),.ack(ack),.tick(tick),
        .switching(switching),.pcm(pcm),.mode(mode),.rows(rows));
`ifdef TAIL_GATE
    wire [5:0] gpins;wire gvalid,gack,gtick,gswitching;wire [15:0] gpcm;wire [1:0] gmode;wire [3:0] grows;
    tail_gate_audio gate(.clk(clk),.sysclk(sysclk),.rst_n(rst_n),.contacts(contacts),.pluck(pluck),
        .command_valid(command_valid),.command_mode(command_mode),.pins(gpins),.valid(gvalid),.ack(gack),.tick(gtick),
        .switching(gswitching),.pcm(gpcm),.mode(gmode),.rows(grows));
`endif
    tail_before_four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.GAME_CUE_ENABLE(1),.I2S_ENABLE(1),
        .USE_PIANO(1),.CONTROL_PHASE_VALUE_BITS(27),.PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1),.VIBRATO_ENABLE(1)) oracle(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(1'b0),.stable_fret_id(16'd0),.pluck_valid(4'd0),.velocity_level(8'haa),
        .timbre_select(1'b0),.rock_select(1'b0),.chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .sample_tick(oracle_tick),.pcm_mix_valid(oracle_valid),.pcm_mix(oracle_pcm),.voice_active(oracle_active),.voice_pcm(),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid(),
        .external_note_on(reference.u_audio.note_on),.external_note_off(reference.u_audio.note_off),
        .external_force_release(reference.u_audio.force_release),.external_phase_inc(expected_target),
        .external_vibrato_enable(reference.u_audio.performance_vibrato),.game_cue_enable(1'b0),.game_miss_event(1'b0),
        .control_pipeline_idle(),.control_timbre_busy(),.dac_bclk(opins[0]),.dac_lrck(opins[1]),.dac_din(opins[2]),
        .i2s_bclk(opins[3]),.i2s_ws(opins[4]),.i2s_data(opins[5]));
    always @(posedge clk)if(rst_n)begin
        if(reference.u_audio.stable_valid && mode==1 && !switching)
            for(integer s=0;s<4;s=s+1)if(allow_slide[s] && reference.u_audio.fret_id[s*4+:4]!=0)
                expected_target[s*32+:32]<=phase_rom[s*9+reference.u_audio.fret_id[s*4+:4]];
        #2;
        if(valid!==oracle_valid || tick!==oracle_tick || rpins!==opins ||
           reference.u_audio.final_pcm!==oracle_pcm || reference.u_audio.active!==oracle_active)
            $fatal(1,"FAIL: independent held/slide pitch PCM oracle step%0d sample%0d got%h expected%h",step,samples,reference.u_audio.target_phase,expected_target);
        if(valid)pcm_checks=pcm_checks+1;
`ifdef TAIL_GATE
        if({gpins,gvalid,gack,gtick,gswitching,gpcm,gmode,grows}!=={rpins,valid,ack,tick,switching,pcm,mode,rows})
            $fatal(1,"FAIL: actual audio-child VG mismatch step%0d sample%0d",step,samples);
`endif
    end
    always @(negedge clk)if(rst_n)begin
        if(tick)samples=samples+1;
        if(reference.u_audio.note_on!=0)begin
            if(reference.u_audio.note_on!==expected_attack)$fatal(1,"FAIL: synthetic/lost Attack step%0d",step);
            expected_attack=0;attacks=attacks+1;
        end
        for(integer s=0;s<4;s=s+1)if(reference.u_audio.fret_release[s])release_counts[s]=release_counts[s]+1;
        if(mode==1 && !switching && (reference.u_audio.note_off!=0 || reference.u_audio.force_release!=0))
            $fatal(1,"FAIL: fret input hard-released the natural tail");
        if(reference.u_audio.u_chain.deadline_miss || reference.u_audio.u_chain.performance_vibrato.deadline_miss)
            $fatal(1,"FAIL: production audio/vibrato deadline");
    end
    task check(input bit okay,input [511:0] label_text);
        if(!okay)$fatal(1,"FAIL: %0s step%0d sample%0d",label_text,step,samples);
    endtask
    task physical(input [15:0] frets);
        @(negedge clk);
        for(integer s=0;s<4;s=s+1)contacts[s*8+:8]=frets[s*4+:4]==0 ? 0 : 8'b1<<(frets[s*4+:4]-1);
    endtask
    task stable_frets(input [15:0] frets);
        wait(reference.u_audio.fret_id==frets && reference.u_audio.stable_valid);@(negedge clk);
    endtask
    task wait_samples(input integer count);
        repeat(count)begin @(negedge clk);while(!tick)@(negedge clk);end
        @(negedge clk);
    endtask
    task strike(input [3:0] mask,input [15:0] expected_frets);
        @(negedge clk);
        for(integer s=0;s<4;s=s+1)if(mask[s])expected_target[s*32+:32]=phase_rom[s*9+expected_frets[s*4+:4]];
        expected_attack=mask;pluck=mask;
        repeat(2)@(negedge clk);pluck=0;wait_samples(3);
        check(expected_attack==0,"real pluck was not consumed");
    endtask
    task command(input [1:0] value);
        @(negedge clk);while(tick)@(negedge clk);
        // The existing router freezes the currently audible (possibly
        // modulated) pitch when beginning its graceful mode-exit release.
        // Mirror that public transition, independently of the new fret policy.
        if(mode==1)expected_target=reference.u_audio.audible_phase;
        command_mode=value;command_valid=1;
        wait(ack);@(negedge clk);command_valid=0;repeat(4)@(negedge clk);
    endtask
    integer before_release;
    reg [127:0] before_pitch;
    initial begin
        $readmemh("../../mem/note_phase_inc.mem",phase_rom);
        for(integer s=0;s<4;s=s+1)release_counts[s]=0;
        repeat(32)@(negedge clk);rst_n=1;command(1);step=1;
        physical(16'h1111);stable_frets(16'h1111);strike(15,16'h1111);wait_samples(32);
        // A3ms release is deliberately too short for the original5-frame
        // stable zero, but all four qualified row releases must still lock.
        allow_slide=0;before_pitch=expected_target;physical(0);repeat(36864)@(negedge clk);
        physical(16'h3333);stable_frets(16'h3333);wait_samples(1024);
        check(reference.u_audio.target_phase==before_pitch && reference.u_audio.active==15,"first-fret tails retuned/ended after third-fret preparation");
        check(reference.u_audio.p2.u_router.performance.tail_locked==15,"short-release four-string locks");
        step=2;strike(1,16'h3333);allow_slide=1;
        // Overlap old/new contacts: no empty matrix sample is possible.
        @(negedge clk);contacts[7:0]=8'h14;stable_frets(16'h3335);wait_samples(1100);
        check(reference.u_audio.audible_phase[31:0]==phase_rom[5],"continuous contact move lost slide");
        before_release=release_counts[0];@(negedge clk);contacts[7:0]=0;repeat(6144)@(negedge clk);
        contacts[7:0]=8'h20;stable_frets(16'h3336);wait_samples(1100);
        check(release_counts[0]==before_release && reference.u_audio.audible_phase[31:0]==phase_rom[6],"single dropout falsely locked a continuous slide");
        step=3;allow_slide=0;physical(16'h3330);stable_frets(16'h3330);
        physical(16'h3332);stable_frets(16'h3332);wait_samples(256);
        check(reference.u_audio.target_phase[31:0]==phase_rom[6],"long release then second fret retuned old sixth-fret tail");
        physical(16'h3330);stable_frets(16'h3330);strike(1,16'h3330);
        check(reference.u_audio.target_phase[31:0]==phase_rom[0],"real open restrike failed");
        step=4;allow_slide=1;physical(16'h1111);stable_frets(16'h1111);strike(15,16'h1111);allow_slide=0;
        for(integer tap=0;tap<3;tap=tap+1)begin
            physical(0);repeat(860160)@(negedge clk);physical(16'h1111);
            stable_frets(16'h1111);wait_samples(128);
        end
        check(reference.u_audio.performance_vibrato==15 && reference.u_audio.active==15,"three same-fret release/repress gestures lost vibrato");
        before_pitch=reference.u_audio.audible_phase;wait_samples(9000);
        check(reference.u_audio.audible_phase!=before_pitch,"vibrato not audible after tail lock");
        step=5;physical(16'h1112);stable_frets(16'h1112);wait_samples(2);
        check(reference.u_audio.performance_vibrato==14 && reference.u_audio.target_phase[31:0]==phase_rom[1],"changed prepared fret did not independently cancel vibrato while preserving tail");
        before_release=release_counts[1];@(negedge clk);contacts[15:8]=0;
        wait(release_counts[1]>before_release);repeat(4)@(negedge clk);
        check(reference.u_audio.performance_vibrato==12,"short qualified release failed to cancel only its vibrato");
        contacts[15:8]=8'h01;wait_samples(512);strike(4,16'h1112);
        check(reference.u_audio.performance_vibrato==8,"one real restrike cancelled neighboring vibrato");
        step=6;command(0);check(reference.u_audio.performance_vibrato==0,"mode exit retained vibrato");
        wait_samples(32);command(2);wait_samples(64);
        check(reference.u_audio.performance_vibrato==0,"game countdown enabled performance vibrato");
        $display("PASS: production audio/matrix tail lock first-release-third-fret, continuous overlap slides, one-dropout rejection, real open/prepared restrikes, four independent voices, three production-timed taps and original cancellation/modes; %0d audio samples/%0d independent frozen-chain PCM checks/%0d real Attack bursts",samples,pcm_checks,attacks);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"FAIL: tail audio watchdog step%0d",step);end
endmodule
