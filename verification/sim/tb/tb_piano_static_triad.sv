`timescale 1ns/1ps
// Fixed C4/E4/G4, dry full board chain: isolates the listening question from
// deliberate fret slides, fourth-voice bass, effects and retriggers in the stress AB.
module tb_piano_static_triad;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable=0,recording=0;
    reg [3:0] pluck=0,expected_active=0;
    reg [15:0] frets=16'h0553;
    wire [1:0] tick;
    wire [7:0] active;
    legacy_four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) old(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(1'b0),.rock_select(1'b0),
        .chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .sample_tick(tick[0]),.voice_active(active[3:0]),.pcm_mix_valid(),.pcm_mix(),
        .voice_pcm(),.dac_bclk(),.dac_lrck(),.dac_din(),.display_phase_inc(),
        .display_note_on(),.display_voice_sample_valid());
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) dut(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(1'b0),.rock_select(1'b0),
        .chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),
        .sample_tick(tick[1]),.voice_active(active[7:4]),.pcm_mix_valid(),.pcm_mix(),
        .voice_pcm(),.dac_bclk(),.dac_lrck(),.dac_din(),.display_phase_inc(),
        .display_note_on(),.display_voice_sample_valid(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );
    integer f0,f1,frames=0,run_id=0,n;
    reg [127:0] fixed_phase;
    always @(posedge clk)begin
        #2;
        if(rst_n && recording && dut.pcm16_left_valid)begin
            if(!old.pcm16_left_valid || tick[0]!==tick[1] ||
               dut.deadline_miss!=0 || old.deadline_miss!=0 ||
               $isunknown({dut.pcm16_left_out,dut.pcm16_right_out}))
                $fatal(1,"FAIL: static triad cadence, deadline or unknown");
            if(dut.phase_inc!==fixed_phase || old.phase_inc!==fixed_phase)
                $fatal(1,"FAIL: static diagnostic pitch changed");
            if(active[3:0]!==expected_active || active[7:4]!==expected_active)
                $fatal(1,"FAIL: unexpected active voice %h wanted %h",active,expected_active);
            if(dut.pcm16_left_out==16'sh7fff || dut.pcm16_left_out==16'sh8000 ||
               dut.pcm16_right_out==16'sh7fff || dut.pcm16_right_out==16'sh8000 ||
               old.pcm16_left_out==16'sh7fff || old.pcm16_left_out==16'sh8000 ||
               old.pcm16_right_out==16'sh7fff || old.pcm16_right_out==16'sh8000)
                $fatal(1,"FAIL: static piano clipping");
            $fwrite(f0,"%0d %04h %04h %06h %06h\n",run_id,old.pcm16_left_out,
                old.pcm16_right_out,old.pcm_left_scaled,old.pcm_right_scaled);
            $fwrite(f1,"%0d %04h %04h %06h %06h\n",run_id,dut.pcm16_left_out,
                dut.pcm16_right_out,dut.pcm_left_scaled,dut.pcm_right_scaled);
            frames=frames+1;
        end
    end
    initial begin
        f0=$fopen("static_triad_legacy.txt","w");f1=$fopen("static_triad_procedural.txt","w");
        if(!f0||!f1)$fatal(1,"FAIL: static diagnostic file open");
        for(n=0;n<4;n=n+1)begin
            @(negedge clk);recording=0;rst_n=0;pluck=0;stable=0;
            repeat(8)@(negedge clk);rst_n=1;
            @(negedge clk);stable=1;@(negedge clk);stable=0;
            repeat(512)@(negedge clk);
            fixed_phase=dut.phase_inc;
            // V0=G4, V1=E4, V2=C4; V3 is never plucked.
            expected_active=n==3 ? 4'b0111 : (4'b0001<<n);
            run_id=n;frames=0;pluck=expected_active;
            @(negedge clk);pluck=0;
            wait(active[3:0]==expected_active && active[7:4]==expected_active);
            // Drain the previous silent frame's short FX/PCM pipeline while
            // the first struck frame is still in the 233-clock source schedule.
            repeat(64)@(negedge clk);recording=1;
            wait(frames>=(n==3 ? 96000 : 48000));
        end
        @(negedge clk);recording=0;$fclose(f0);$fclose(f1);
        $display("PASS: static dry C4/E4/G4 solos and 96000-frame triad, exactly three voices, fixed frets, no FX/harmony/retrigger, no clipping/deadline");
        $finish;
    end
    initial begin #660000000;$fatal(1,"FAIL: static piano diagnostic timeout");end
endmodule
