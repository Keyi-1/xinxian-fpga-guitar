`timescale 1ns/1ps
// FULL sound-engine test: fret order/release cannot reset envelope age, damp
// the voice or change its natural lifetime. Only the test timeout is shortened.
module tb_guitar_open_release;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stable=0,timbre=0,rock=0,sustain=0,chorus=0,room=0,harmony=0;
    reg [15:0] fret=0;
    reg [3:0] pluck=0;
    wire tick,valid;
    wire [3:0] active;
    wire [95:0] pcm;
    wire [127:0] pitch;
    wire [3:0] attack;
    four_string_board_audio_chain #(.USE_PIANO(1),.PIANO_MODES(32),
        .PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1),.SAMPLE_DIV(256),
        .SLIDE_SAMPLES(960)) dut(
        .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(stable),.stable_fret_id(fret),
        .pluck_valid(pluck),.velocity_level(8'haa),.timbre_select(timbre),.rock_select(rock),
        .sustain_enable(sustain),.chorus_enable(chorus),.reverb_enable(room),.harmony_enable(harmony),
        .sample_tick(tick),.pcm_mix_valid(valid),.pcm_mix(),.voice_active(active),.voice_pcm(pcm),
        .dac_bclk(),.dac_lrck(),.dac_din(),.display_phase_inc(pitch),
        .display_note_on(attack),.display_voice_sample_valid(),
        .i2s_bclk(),.i2s_ws(),.i2s_data()
    );
    // Preserve all 32 components and ROM values. Shorten only MAX_SAMPLES in
    // the bench, so expiration can be checked without simulating seconds.
    defparam dut.g_piano.u_core.voice[0].u_voice.MAX_SAMPLES=4096;
    defparam dut.g_piano.u_core.voice[1].u_voice.MAX_SAMPLES=4096;
    defparam dut.g_piano.u_core.voice[2].u_voice.MAX_SAMPLES=4096;
    defparam dut.g_piano.u_core.voice[3].u_voice.MAX_SAMPLES=4096;
    localparam [127:0] OPEN={32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F};
    integer accepted[0:3],elapsed[0:3],age_expected[0:3];
    integer nonzero=0;
    always @(posedge clk)if(rst_n && dut.voice_sample_valid && pcm!=0)nonzero++;
    genvar s;
    generate for(s=0;s<4;s++)begin : lifetime_check
        reg old_on,old_active;
        integer old_age;
        always @(posedge clk)begin
            if(!rst_n)begin accepted[s]=0;elapsed[s]=0;age_expected[s]=0;end
            else begin
                if(dut.note_off!==0)$fatal(1,"FAIL: fret duration generates damping");
                if(tick)begin
                    old_on=attack[s];old_active=active[s];old_age=age_expected[s];
                    #1;
                    if(old_on)begin accepted[s]++;elapsed[s]=0;age_expected[s]=0;end
                    else if(old_active && old_age<4095)begin
                        elapsed[s]++;
                        age_expected[s]=!sustain || elapsed[s]<=2048 ? elapsed[s] :
                            2048+(elapsed[s]-2048)/4;
                    end
                    if(old_on || (old_active && old_age<4095))begin
                        if(!active[s] || dut.g_piano.u_core.voice[s].u_voice.age!==age_expected[s])
                            $fatal(1,"FAIL: string %0d natural age altered by fret, got=%0d expected=%0d",s,
                                dut.g_piano.u_core.voice[s].u_voice.age,age_expected[s]);
                        if(dut.g_piano.u_core.voice[s].u_voice.releasing ||
                           dut.g_piano.u_core.voice[s].u_voice.release_level!==24'hffffff)
                            $fatal(1,"FAIL: string %0d enters Release on fret change",s);
                    end else if(old_active && active[s])
                        $fatal(1,"FAIL: natural expiration did not end string %0d",s);
                end
                if(dut.g_piano.u_core.deadline_miss!=0)$fatal(1,"FAIL: FULL sound deadline");
            end
        end
    end endgenerate
    task select_fret(input [15:0] value);
        @(negedge clk);stable=1;fret=value;
        @(negedge clk);stable=0;
    endtask
    task wait_samples(input integer count);
        repeat(count)@(posedge tick);
        @(negedge clk);
    endtask
    task real_pluck;
        @(negedge clk);pluck=15;
        @(negedge clk);pluck=0;
        wait(accepted[0]==1);@(negedge clk);
    endtask
    integer mode,guard,i;
    initial begin
        for(mode=0;mode<4;mode++)begin
            @(negedge clk);rst_n=0;pluck=0;stable=0;fret=0;
            timbre=(mode==1);rock=(mode==2);sustain=(mode==3);
            chorus=(mode==2);room=(mode==2);harmony=(mode==2);
            repeat(5)@(negedge clk);rst_n=1;
            select_fret(mode==1 ? 16'h0000 : 16'h8888);
            wait_samples(10);
            if(active || accepted[0])$fatal(1,"FAIL: frets alone start sound");
            real_pluck();wait_samples(32);
            if(mode==1)begin select_fret(16'h8888);wait_samples(1100);end
            select_fret(0);wait_samples(1100);
            if(active!=15 || pitch!==OPEN || accepted[0]!=1 || accepted[1]!=1 ||
               accepted[2]!=1 || accepted[3]!=1)
                $fatal(1,"FAIL: mode %0d open continuation/retrigger/four-voice pitch",mode);
            // A second press/release during the same decaying note remains pitch-only.
            select_fret(16'h1111);wait_samples(100);
            select_fret(0);wait_samples(100);
            guard=0;
            while(active!=0 && guard<14000)begin wait_samples(1);guard++;end
            if(active || guard>=14000)$fatal(1,"FAIL: natural lifetime timeout");
            select_fret(16'h8888);wait_samples(20);
            select_fret(0);wait_samples(20);
            if(active || accepted[0]!=1 || accepted[1]!=1 || accepted[2]!=1 || accepted[3]!=1)
                $fatal(1,"FAIL: fret movement restarts an expired voice");
            $display("PASS: FULL open-release mode=%0d, four natural envelope ages/lifetimes, no damp/retrigger; unchanged 32-mode sound engine",mode);
        end
        if(nonzero<100)$fatal(1,"FAIL: no audible PCM coverage");
        $display("PASS: fret duration independent of sound lifetime; piano/bright/wah, sustain, chorus/room/fifth and both fret/pluck orders");
        $finish;
    end
endmodule
