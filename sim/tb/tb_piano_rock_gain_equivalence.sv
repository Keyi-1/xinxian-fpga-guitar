`timescale 1ns/1ps
module tb_piano_rock_gain_equivalence;
    GSR GSR(.GSRI(1'b1));
    `include "rock_coeffs.vh"
    reg clk=0;always #5 clk=~clk;
    reg rst=0,ce=0,on=0,off=0,force_stop=0;
    reg [1:0] velocity=0;
    reg [31:0] phase=32'd70150316;
    reg [8:0] bright=0,rock=0;
    reg sustain=1,harmony=1;
    wire va,vb,aa,ab,ba,bb,da,db;
    wire signed [23:0] pa,pb;wire [1:0] profile_a,profile_b;
    `define ARGS .clk(clk),.rst_n(rst),.sample_ce(ce),.note_on(on),.note_off(off), \
        .velocity_level(velocity),.phase_inc(phase),.timbre_blend(bright),.rock_blend(rock), \
        .sustain_enable(sustain),.harmony_enable(harmony),.force_release(force_stop)
    piano_voice_core #(.MODES(32),.HAMMER_ENABLE(1),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) dut(
        `ARGS,.sample_valid(va),.pcm_out(pa),.active(aa),.busy(ba),.deadline_miss(da),.profile(profile_a));
    accepted_p3_source_voice #(.MODES(32),.HAMMER_ENABLE(1),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) frozen(
        `ARGS,.sample_valid(vb),.pcm_out(pb),.active(ab),.busy(bb),.deadline_miss(db),.profile(profile_b));
    `undef ARGS
    integer samples=0,i,j,mode,level;
    reg read_enable=0;reg [6:0] address=0;wire [15:0] data;
    piano_rock_gain_rom table_dut(.clk(clk),.read_enable(read_enable),.address(address),.data(data));
    always @(negedge clk)if(rst)begin
        if({va,pa,aa,ba,da,profile_a,dut.velocity_product}!=={vb,pb,ab,bb,db,profile_b,frozen.velocity_product})
            $fatal(1,"FAIL: frozen piano voice differs sample%0d velocity%0d",samples,velocity);
        if(va)samples=samples+1;
        if(da || db)$fatal(1,"FAIL: gain ROM deadline");
        if(dut.state==4 && dut.rock_gain_read!==rock_gain_for(dut.profile,dut.local_mode))
            $fatal(1,"FAIL: gain not ready before LOOKUP");
        if(dut.state==3 && dut.mode_phase_value!==frozen.mode_phase[frozen.mode_index])
            $fatal(1,"FAIL: synchronous phase state differs mode%0d",dut.mode_index);
        if(dut.state==4 && dut.bright_gain_value!==frozen.bright_gain[frozen.mode_index])
            $fatal(1,"FAIL: synchronous gain state differs mode%0d",dut.mode_index);
    end
    task automatic sample(input bit strike,stop,release_now);
        begin
            @(negedge clk);ce=1;on=strike;off=stop;force_stop=release_now;
            @(negedge clk);ce=0;on=0;off=0;force_stop=0;
            repeat(254)@(negedge clk);
        end
    endtask
    initial begin
        for(i=0;i<128;i=i+1)begin
            @(negedge clk);address=i;read_enable=1;@(posedge clk);#1;
            if(data!==rock_gain_for(i/32,i%32))$fatal(1,"FAIL: ROM coefficient%0d",i);
        end
        @(negedge clk);read_enable=0;rst=1;
        for(mode=0;mode<3;mode=mode+1)begin
            bright=mode==1 ? 256 : 0;rock=mode==2 ? 256 : 0;
            for(level=0;level<4;level=level+1)begin
                velocity=level;
                case(level)0:phase=32'd13139206;1:phase=32'd30000000;default:phase=32'd70150316;endcase
                sample(1,0,0);
                for(j=0;j<2304;j=j+1)begin
                    // Cross the wah ramp/age boundary and exercise all
                    // profile/mode gain addresses, including harmony folding.
                    sample(0,j==2100,0);
                end
                sample(0,0,1);repeat(1452)sample(0,0,0);
            end
        end
        // Inputs can change while a frame is being calculated; attack seed
        // settings must stay at the accepted sample boundary.
        phase=32'd30000000;velocity=3;harmony=1;rock=256;
        fork
            begin sample(1,0,0);end
            begin repeat(80)@(negedge clk);harmony=0;rock=0;phase=32'd70150316;end
        join
        repeat(32)sample(0,0,0);
        // Reset during a modal pass. BSRAM contents remain, but every first
        // post-reset read must act exactly like a freshly cleared array.
        @(negedge clk);ce=1;on=1;@(negedge clk);ce=0;on=0;
        repeat(20)@(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
        repeat(16)sample(0,0,0);sample(1,0,0);repeat(64)sample(0,0,0);
        $display("PASS: all128 exact gain ROM entries; original frozen32-mode voice %0d samples, all4 velocities/3 timbres/3 pitch profiles/hammer/harmony/sustain/wah age boundary/release; gain ready within existing LOAD->LOOKUP and zero deadlines",samples);
        $finish;
    end
    initial begin #150000000;$fatal(1,"FAIL: rock gain ROM watchdog");end
endmodule
