`timescale 1ns/1ps
module tb_quarter_voice_preservation;
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
    accepted_quarter_voice #(.MODES(32),.HAMMER_ENABLE(1),.CONTROL_ENABLE(1),.ROCK_ENABLE(1),.FORCE_RELEASE_ENABLE(1)) frozen(
      `IN,.sample_valid(vb),.pcm_out(pb),.active(ab),.busy(bb),.deadline_miss(db),.profile(fb));
    `undef IN
    integer tone,pitch,i,samples=0,low_samples=0,unchanged_samples=0;
    reg signed [63:0] difference,new_energy,old_energy;
    always @(negedge clk)if(rst)begin
      if({va,aa,ba,da,fa,dut.state,dut.velocity_source,dut.release_level}!==
         {vb,ab,bb,db,fb,frozen.state,frozen.velocity_source,frozen.release_level})
        $fatal(1,"FAIL: gain-only change altered synthesis/state/envelope");
      if(da || db)$fatal(1,"FAIL: dynamics deadline");
      if((level==0 || level==3) && {pa,dut.velocity_product}!=={pb,frozen.velocity_product})
        $fatal(1,"FAIL: unchanged levels0/3 changed");
      if(aa && ((level==1 && (dut.velocity_gain!==128 || frozen.velocity_gain!==160)) || (level==2 && (dut.velocity_gain!==192 || frozen.velocity_gain!==208))))
        $fatal(1,"FAIL: wrong low-level gain");
      if(va)begin
        samples=samples+1;
        if(level==1 || level==2)begin
          // Two integer gain/release roundings bound the dry PCM error.
          // Reset before each attack keeps both continuity terms at zero.
          difference=level==1 ? $signed(pa)*64'sd5-$signed(pb)*64'sd4 : $signed(pa)*64'sd13-$signed(pb)*64'sd12;
          if(difference>(level==1 ? 10 : 26) || difference < -(level==1 ? 10 : 26))$fatal(1,"FAIL: mid PCM not128/160 or192/208 scaling within rounding");
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
        for(i=0;i<((grade==1 || grade==2) ? 2304 : 256);i=i+1)sample(0,0);
        sample(0,1);repeat(64)sample(0,0);
        if((grade==1 || grade==2) && (new_energy<=0 || new_energy>=old_energy))$fatal(1,"FAIL: low level not quieter");
      end
      $display("PASS: frozen pre-tuning voice,3 timbres x3 pitch profiles x4 levels; %0d total/%0d middle128-192 scaled/%0d levels0-and3 exact PCM samples,unchanged modal source/envelope/schedule,hammer/harmony/sustain/wah age/release,zero deadlines",samples,low_samples,unchanged_samples);$finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: dynamics voice watchdog");end
endmodule
