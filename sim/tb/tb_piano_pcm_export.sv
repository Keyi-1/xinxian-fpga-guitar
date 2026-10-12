`timescale 1ns/1ps
// Same real board audio chain, accelerated sample/DAC dividers 64/1. All ROM,
// DDS, envelope and room equations still use the 48-kHz logical sample rate.
// Shipped 256/4 cadence is checked separately by the default-main bench.
module tb_piano_pcm_export;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable=0;
    reg [15:0] frets=16'h0553; // G4 / E4 / C4 / open D3
    reg [3:0] pluck=0;
    wire tick0,tick1,valid0,valid1;
    wire [3:0] active0,active1;
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_HAMMER_ENABLE(0),.SAMPLE_DIV(64),.REF_DIV(1)) body (
        .rock_select(1'b0),
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(1'b0),
        .chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),.sample_tick(tick0),
        .pcm_mix_valid(valid0),.pcm_mix(),.voice_active(active0),.voice_pcm(),
        .dac_bclk(),.dac_lrck(),.dac_din(),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid());
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_HAMMER_ENABLE(1),.SAMPLE_DIV(64),.REF_DIV(1)) hammer (
        .rock_select(1'b0),
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(frets),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(1'b0),
        .chorus_enable(1'b0),.sustain_enable(1'b0),.harmony_enable(1'b0),.reverb_enable(1'b0),.sample_tick(tick1),
        .pcm_mix_valid(valid1),.pcm_mix(),.voice_active(active1),.voice_pcm(),
        .dac_bclk(),.dac_lrck(),.dac_din(),
        .display_phase_inc(),.display_note_on(),.display_voice_sample_valid());
    integer file0,file1,frames=0,full_seen=0,clips=0;
    reg recording=0;
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            if(tick0!==tick1 || valid0!==valid1 || active0!==active1 ||
               hammer.deadline_miss!=0 || body.deadline_miss!=0)
                $fatal(1,"FAIL: piano cadence/lifecycle/deadline");
            if(recording && hammer.pcm16_left_valid)begin
                if(!body.pcm16_left_valid)$fatal(1,"FAIL: piano PCM16 cadence");
                $fwrite(file0,"%04h %04h\n",body.pcm16_left_out,body.pcm16_right_out);
                $fwrite(file1,"%04h %04h\n",hammer.pcm16_left_out,hammer.pcm16_right_out);
                frames=frames+1;
                if(active1==15)full_seen=1;
                if(hammer.pcm16_left_out==16'sh7fff || hammer.pcm16_left_out==16'sh8000 ||
                   hammer.pcm16_right_out==16'sh7fff || hammer.pcm16_right_out==16'sh8000) clips=clips+1;
            end
        end
    end
    task select(input [15:0] f);
        @(negedge clk);frets=f;stable=1;
        @(negedge clk);stable=0;
    endtask
    task launch(input [3:0] mask);
        @(negedge clk);pluck=mask;
        @(negedge clk);pluck=0;
    endtask
    integer n;
    initial begin
        file0=$fopen("piano_body_pcm16.txt","w");file1=$fopen("piano_hammer_pcm16.txt","w");
        if(!file0||!file1)$fatal(1,"FAIL: piano export files");
        repeat(8)@(negedge clk);rst_n=1;
        select(16'h0553);repeat(256)@(negedge clk);
        if(active1!=0)$fatal(1,"FAIL: fret selection made piano sound");
        recording=1;
        for(n=0;n<3;n=n+1)begin
            select(16'h0553);launch(4'b0100>>n); // C, E, G
            wait(frames>=(n*38400+21600));select(0);
            wait(frames>=(n+1)*38400);
        end
        for(n=0;n<2;n=n+1)begin
            select(16'h0553);launch(4'b0111);
            wait(frames>=(115200+n*57600+43200));select(0);
            wait(frames>=(115200+(n+1)*57600));
        end
        select(16'h5553);launch(4'b1111); // Add G3 bass, same C/E/G chord.
        wait(frames>=259200);select(0);
        wait(frames>=288000);recording=0;
        if(!full_seen||clips!=0)$fatal(1,"FAIL: missing fourth voice or clipping %0d",clips);
        $fclose(file0);$fclose(file1);
        $display("PASS: 288000 actual RTL PCM16 stereo frames per variant; C4/E4/G4 singles, repeated triads, G3 bass four-note chord; no clipping/deadline/lifecycle differences");
        $finish;
    end
    initial begin #190000000;$fatal(1,"FAIL: piano PCM timeout");end
endmodule
