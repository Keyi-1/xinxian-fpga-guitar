`timescale 1ns/1ps
module tb_game_p2_engine_gate;
    GSR GSR(.GSRI(1'b1));
    `include "p2_gate_pair.vh"
    reg [4:0] inject_command=0;
    reg inject_valid=0;
    integer samples=0,s,origin,nonzero=0;
    integer progress_log;
    initial begin progress_log=$fopen("engine_progress.log","w");$fwrite(progress_log,"started\n");$fflush(progress_log);end
    initial begin
        `include "engine_force.vh"
    end
    always @(posedge audio_clk)begin
        #2;
        if(reference.audio_rst_n)begin
            if(gaudio!==raudio)begin
                $display("gate pins=%b RTL pins=%b; PCM L/R gate=%h/%h RTL=%h/%h",gaudio,raudio,
                    gate.u_audio.u_chain.pcm16_left_out,gate.u_audio.u_chain.pcm16_right_out,
                    reference.u_audio.u_chain.pcm16_left_out,reference.u_audio.u_chain.pcm16_right_out);
                $display("time gate=%0d RTL=%0d countdown=%b/%b left=%d/%d launch=%b/%b",
                    `GCORE.song_time_Z,`RCORE.song_time,`GCORE.countdown_Z,`RCORE.countdown,
                    `GCORE.countdown_left,`RCORE.countdown_left,`GCORE.launch,`RCORE.launch);
                $fatal(1,"FAIL: P2 synthesized musical PT8211/I2S output differs sample=%0d",samples);
            end
            if(reference.u_audio.sample_tick)samples=samples+1;
            if(gaudio[2] || gaudio[6])nonzero=nonzero+1;
            if(reference.u_audio.sample_tick && samples%256==0)begin
                $display("Progress: musical pins identical through sample %0d",samples);
                $fwrite(progress_log,"samples=%0d\n",samples);$fflush(progress_log);
            end
        end
    end
    task select_song(input integer song);
        $display("Progress: selecting synthesized slot %0d at sample %0d",song,samples);
        $fwrite(progress_log,"select slot=%0d samples=%0d\n",song,samples);$fflush(progress_log);
        @(negedge audio_clk);inject_command={song[2:0],2'd3};inject_valid=1;
        wait(reference.dst_command_ack);
        $display("Progress: slot %0d release/selection acknowledged",song);
        $fwrite(progress_log,"ack slot=%0d samples=%0d\n",song,samples);$fflush(progress_log);
        @(negedge audio_clk);inject_valid=0;
        wait(`RCORE.countdown);
        // Only accelerate the two-second wait. The score state machine and
        // actual note/audio arithmetic still run at one sample per 256 clocks.
        force `RCORE.countdown_left=32'd1;
        force `GCORE.countdown_left=32'd1;
        @(posedge audio_clk);
        while(!reference.u_audio.sample_tick)@(posedge audio_clk);
        #3;release `RCORE.countdown_left;release `GCORE.countdown_left;
        origin=samples;nonzero=0;wait(samples>=origin+1100);
        if(nonzero==0)$fatal(1,"FAIL: synthesized selected song/timbre silent");
        if(reference.event_led[2]!==0 || gate.event_led[2]!==0)
            $fatal(1,"FAIL: actual sustain button path did not enable sustain");
        $display("Progress: synthesized song %0d / tone %0d musical output matches at sample %0d",song,song==0 ? 0 : song==2 ? 2 : 1,samples);
    endtask
    initial begin
        wait(reference.lcd_rst_n);repeat(10)@(negedge sys_clk);
        space_key=0; // Actual key debounce enables sustain before the first exit.
        @(negedge sys_clk);sys_run=0;
        for(s=0;s<4;s=s+1)select_song(s);
        @(negedge audio_clk);inject_command=0;inject_valid=1;wait(reference.dst_command_ack);
        @(negedge audio_clk);inject_valid=0;repeat(300)@(negedge audio_clk);
        $display("PASS: synthesized P2 engine, shared static ROM, four selected previews, actual three timbres and musical PT8211/I2S bit-exact to RTL through %0d samples; final sustained-independent release acknowledged",samples);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: engine gate watchdog sample=%0d",samples);end
endmodule
