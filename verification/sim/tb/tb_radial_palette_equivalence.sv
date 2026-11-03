`timescale 1ns/1ps
module tb_radial_palette_equivalence;
reg clk=0;always #10 clk=~clk;
reg rst_n=0,frame_start=0,visual_update=0;
reg [8:0] x=0,y=0;
reg [11:0] mask=0;
reg [3:0] active=0,flash=0;
reg [43:0] hz=0;
reg [15:0] fret=0,level=0;
reg [31:0] strikes=0;
reg [159:0] targets=0;
wire [17:0] old_rgb,new_rgb;wire [3:0] old_curve,new_curve;
`define INPUTS .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.visual_update(visual_update),.x(x),.y(y),.mask(mask),.voice_active(active),.flash(flash),.hz(hz),.fret(fret),.level(level),.strikes(strikes),.targets(targets)
guitar_radial_palette_frozen reference(`INPUTS,.rgb(old_rgb),.curve_active(old_curve));
guitar_radial_palette probe(`INPUTS,.rgb(new_rgb),.curve_active(new_curve));
integer f,i,p,px,py,checked=0,seed=32'h4d454741,unused;
task pixel(input integer xx,yy);
begin
 @(negedge clk);x=xx;y=yy;mask=$urandom;
 repeat(6)@(negedge clk);
 if(new_rgb!==old_rgb || new_curve!==old_curve)
  $fatal(1,"FAIL: palette pixel frame=%0d x=%0d y=%0d old=%h new=%h",f,xx,yy,old_rgb,new_rgb);
 checked=checked+1;
end
endtask
initial begin
 unused=$urandom(seed);
 repeat(8)@(negedge clk);rst_n=1;
 visual_update=1;targets={160{1'b1}};
 @(negedge clk);visual_update=0;
 repeat(17)@(negedge clk);rst_n=0;
 repeat(2)@(negedge clk);rst_n=1;
 for(f=0;f<512;f=f+1)begin
  @(negedge clk);
  for(i=0;i<32;i=i+1)begin
   if(f<32)targets[i*5+:5]=f;
   else if(f<64)targets[i*5+:5]=63-f;
   else if(f<128)targets[i*5+:5]=(i==f-64 ? 31 : 0);
   else if(f<192)targets[i*5+:5]=i[0] ? 31 : 0;
   else if(f>=448)targets[i*5+:5]=0;
   else targets[i*5+:5]=$urandom;
  end
  active=f<448 ? $urandom : 0;flash=$urandom;level=$urandom;hz={$urandom,$urandom};fret=$urandom;
  if(f%7==0)strikes[(f%4)*8+:8]=strikes[(f%4)*8+:8]+1'b1;
  visual_update=1;frame_start=1;
  @(negedge clk);visual_update=0;frame_start=0;
  // FFT targets can update independently during the serial pass. Heights
  // must still match the old parallel update's start-time target snapshot.
  repeat(7)@(negedge clk);targets=~targets;
  repeat(56)@(negedge clk);
  if(!probe.bar_busy)$fatal(1,"FAIL: serial pass ended before bar 63");
  @(negedge clk);
  if(probe.bar_busy)$fatal(1,"FAIL: 64-clock serial blank budget");
  for(i=0;i<64;i=i+1)begin
   if(probe.heights[i]!==reference.heights[i] || probe.peaks[i]!==reference.peaks[i])
    $fatal(1,"FAIL: bar rounding/decay frame=%0d index=%0d",f,i);
  end
  repeat(200)@(negedge clk);
  if(f==31 || f==63 || f==127 || f==191 || f==255 || f==319 || f==447 || f==511)
   for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)pixel(px,py);
  else for(p=0;p<128;p=p+1)pixel($urandom_range(0,479),$urandom_range(0,271));
 end
 $display("PASS: serial radial palette: 512 target/strike frames, every height/peak and %0d pixels equal; mid-pass target changes, edges, attack, decay and silence",checked);
 $finish;
end
initial begin #1000000000;$fatal(1,"FAIL: palette probe watchdog");end
endmodule
