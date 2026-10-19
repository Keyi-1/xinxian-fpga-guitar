`timescale 1ns/1ps
module tb_dynamics_voice_preservation;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst=0,ce=0,on=0,off=0,forced=0;
    reg [1:0] level=0;reg [31:0] phase=0;
    reg [8:0] bright=0,rock=0;reg sustain=1,harmony=1;
    wire va,vb,aa,ab,ba,bb,da,db;wire [1:0] fa,fb;
    wire signed [23:0] pa,pb;
    `define IN .clk(clk),.rst_n(rst),.sample_ce(ce),.note_on(on),.note_off(off),.force_release(forced), \
      .velocity_level(level),.phase_inc(phase),.timbre_blend(bright),.rock_blend(rock),.sustain_enable(sustain),.harmony_enable(harmony)
    piano_voice_core #(.MODES(32),.HAMMER_ENABLE(1),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) dut(
      `IN,.sample_valid(va),.pcm_out(pa),.active(aa),.busy(ba),.deadline_miss(da),.profile(fa));
    accepted_velocity_voice #(.MODES(32),.HAMMER_ENABLE(1),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) frozen(
      `IN,.sample_valid(vb),.pcm_out(pb),.active(ab),.busy(bb),.deadline_miss(db),.profile(fb));
    `undef IN
    integer tone,pitch,i,samples=0,low_samples=0,unchanged_samples=0;
    reg signed [63:0] difference,new_energy,old_energy;
    always @(negedge clk)if(rst)begin
      if({va,aa,ba,da,fa,dut.state,dut.velocity_source,dut.release_level}!==
         {vb,ab,bb,db,fb,frozen.state,frozen.velocity_source,frozen.release_level})
        $fatal(1,"FAIL: gain-only change altered synthesis/state/envelope");
      if(da || db)$fatal(1,"FAIL: dynamics deadline");
      if(level!=0 && {pa,dut.velocity_product}!=={pb,frozen.velocity_product})
        $fatal(1,"FAIL: levels1..3 changed");
      if(level==0 && aa && (dut.velocity_gain!==64 || frozen.velocity_gain!==112))
        $fatal(1,"FAIL: wrong low-level gain");
      if(va)begin
        samples=samples+1;
        if(level==0)begin
          // Two integer gain/release roundings bound the dry PCM error.
          // Reset before each attack keeps both continuity terms at zero.
          difference=$signed(pa)*64'sd7-$signed(pb)*64'sd4;
          if(difference>14 || difference < -14)$fatal(1,"FAIL: low PCM not exact64/112 scaling within rounding");
          new_energy=new_energy+$signed(pa)*$signed(pa);
          old_energy=old_energy+$signed(pb)*$signed(pb);
          low_samples=low_samples+1;
        end else unchanged_samples=unchanged_samples+1;
      end
    end
    task sample(input bit strike,stop);
      @(negedge clk);ce=1;on=strike;forced=stop;
      @(negedge clk);ce=0;on=0;forced=0;repeat(254)@(negedge clk);
    endtask
    initial begin
      for(tone=0;tone<3;tone=tone+1)for(pitch=0;pitch<3;pitch=pitch+1)
      for(integer grade=0;grade<4;grade=grade+1)begin
        @(negedge clk);rst=0;repeat(3)@(negedge clk);
        bright=tone==1 ? 256 : 0;rock=tone==2 ? 256 : 0;level=grade;
        case(pitch)0:phase=13139206;1:phase=30000000;2:phase=70150316;endcase
        new_energy=0;old_energy=0;rst=1;sample(1,0);
        for(i=0;i<(grade==0 ? 2304 : 256);i=i+1)sample(0,0);
        sample(0,1);repeat(64)sample(0,0);
        if(grade==0 && (new_energy<=0 || new_energy>=old_energy))$fatal(1,"FAIL: low level not quieter");
      end
      $display("PASS: frozen pre-tuning voice,3 timbres x3 pitch profiles x4 levels; %0d total/%0d low64-vs112 scaled/%0d levels1..3 exact PCM samples,unchanged modal source/envelope/schedule,hammer/harmony/sustain/wah age/release,zero deadlines",samples,low_samples,unchanged_samples);$finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: dynamics voice watchdog");end
endmodule
