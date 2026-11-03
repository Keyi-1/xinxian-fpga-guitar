`timescale 1ns/1ps
module tb_piano_short_decay;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,tick=0,on=0,off=0,forced=0,sustain=0,harmony=0;
    reg [8:0] bright=0,rock=0;
    reg [1:0] velocity=0;
    reg [31:0] increment=32'd23409859;
    wire valid,old_valid,active,old_active,busy,old_busy,deadline,old_deadline;
    wire signed [23:0] pcm,old_pcm;
    GSR GSR(.GSRI(1'b1));
`define PORTS .clk(clk),.rst_n(rst_n),.sample_ce(tick),.note_on(on),.note_off(off), \
    .force_release(forced),.velocity_level(velocity),.phase_inc(increment), \
    .timbre_blend(bright),.rock_blend(rock),.sustain_enable(sustain),.harmony_enable(harmony)
    piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) dut(
        `PORTS,.sample_valid(valid),.pcm_out(pcm),.active(active),.busy(busy),.deadline_miss(deadline),.profile());
    short_before_piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) frozen(
        `PORTS,.sample_valid(old_valid),.pcm_out(old_pcm),.active(old_active),.busy(old_busy),.deadline_miss(old_deadline),.profile());
`undef PORTS
    integer samples=0,changes=0,identical=0,hammer_checks=0,clocks=0;
    integer old_end=0,new_end=0,fd;
    reg check_equal=0,capture=0;
    reg [15:0] envelopes[0:6143];
    integer a,b,weight,expected,offset;
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            clocks=clocks+1;
            if({valid,busy,deadline}!={old_valid,old_busy,old_deadline} || deadline)
                $fatal(1,"FAIL: audio schedule/deadline");
            if(dut.short_piano_note && dut.frame_age<4096 &&
                {dut.procedural_hammer.u_hammer.value,dut.procedural_hammer.u_hammer.slow,dut.procedural_hammer.u_hammer.fast}
                !== {frozen.procedural_hammer.u_hammer.value,frozen.procedural_hammer.u_hammer.slow,frozen.procedural_hammer.u_hammer.fast})
                $fatal(1,"FAIL: hammer transient changed");
            if(dut.state==5 && dut.local_mode<8)begin
                // Independent ROM addressing/interpolation using the raw note
                // age captured by the unchanged frozen engine.
                offset=dut.short_piano_note ? 2*frozen.frame_age : frozen.frame_age;
                if(offset>131071)offset=131071;
                a=offset/512;b=a==255 ? 255 : a+1;weight=offset%512;
                expected=(envelopes[(dut.profile*8+dut.local_mode)*256+a]*(512-weight)+
                          envelopes[(dut.profile*8+dut.local_mode)*256+b]*weight)/512;
                if(dut.amplitude!==(dut.mode_enabled ? (dut.harmony_mode ? expected/2 : expected) : 0))
                    $fatal(1,"FAIL: independent envelope interpolation at sample%0d",samples);
            end
            if(valid)begin
                samples=samples+1;
                if(check_equal)begin
                    if({pcm,active}!={old_pcm,old_active})$fatal(1,"FAIL: non-piano audio changed");
                    identical=identical+1;
                end
                if(dut.frame_age<4096 && dut.short_piano_note)hammer_checks=hammer_checks+1;
                if(pcm!==old_pcm)changes=changes+1;
                if(capture)$fwrite(fd,"%0d %0d\n",old_pcm,pcm);
            end
        end
    end
    task step;
        begin
            @(negedge clk);tick=1;
            @(negedge clk);tick=0;on=0;off=0;forced=0;
            repeat(254)@(negedge clk);
        end
    endtask
    task strike;
        begin on=1;step();end
    endtask
    integer tone,v,p,n;
    initial begin
        $readmemh("../../mem/piano_envelope.mem",envelopes);
        fd=$fopen("piano_decay_ab.txt","w");
        repeat(4)@(negedge clk);rst_n=1;
        // Every profile, velocity and tone. Exact unchanged PCM for the two
        // other tones; independent measured-body oracle for the piano.
        for(tone=0;tone<3;tone=tone+1)begin
            bright=tone==1 ? 256 : 0;rock=tone==2 ? 256 : 0;
            check_equal=tone!=0;
            for(p=0;p<3;p=p+1)begin
                increment=p==0 ? 32'd23409859 : p==1 ? 32'd29495062 : 32'd35075490;
                for(v=0;v<4;v=v+1)begin
                    rst_n=0;repeat(4)@(negedge clk);rst_n=1;
                    velocity=2'(v);sustain=v[0];harmony=v[1];strike();
                    repeat(1024)step();
                end
            end
        end
        check_equal=0;bright=0;rock=0;sustain=0;harmony=0;velocity=3;increment=32'd29495062;
        capture=1;strike();
        for(n=1;n<=131075;n=n+1)begin
            step();
            if(new_end==0 && !active)new_end=n;
            if(old_end==0 && !old_active)old_end=n;
        end
        capture=0;
        if(new_end!=65536 || old_end!=131072)$fatal(1,"FAIL: natural lifetime new%0d old%0d",new_end,old_end);
        // Retargeting and a timbre change must not change the strike's
        // envelope speed. A real restrike selects the new tone policy.
        strike();repeat(128)step();bright=256;repeat(256)step();
        if(!dut.short_piano_note)$fatal(1,"FAIL: crossfade changed note lifetime policy");
        rst_n=0;repeat(4)@(negedge clk);rst_n=1;
        check_equal=1;strike();repeat(512)step();
        off=1;repeat(128)step();forced=1;repeat(1600)step();
        $fclose(fd);
        if(changes<1000 || identical<24000 || hammer_checks<2048)$fatal(1,"FAIL: coverage");
        $display("PASS: piano body2x independent ROM interpolation; natural lifetime65536/131072 samples; three profiles/four velocities/three tones/sustain/harmony; %0d unchanged non-piano samples, %0d hammer checks, %0d samples/%0d clocks, no deadlines",identical,hammer_checks,samples,clocks);
        $finish;
    end
    initial begin #500000000;$fatal(1,"FAIL: short piano watchdog");end
endmodule
