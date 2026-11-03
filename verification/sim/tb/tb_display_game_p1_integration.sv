`timescale 1ns/1ps
// Real scanner, CDC, 1024-point FFT/bands, curve renderer and game UI.
// The only reference substitution is the independently frozen parallel palette.
module tb_display_game_p1_integration;
reg clk=0,audio_clk=0,rst_n=0;
always #10 clk=~clk;
always #40.690104 audio_clk=~audio_clk;
reg [399:0] snapshot=0;
reg [255:0] game_snapshot=0;
reg [2:0] page=1;
reg pcm_valid=0;
reg signed [23:0] pcm=0;
wire p,h,v,d,l,rp,rh,rv,rd,rl;
wire [5:0] r,g,b,rr,rg,rb;
`define DISPLAY_INPUTS .clk(clk),.rst_n(rst_n),.audio_clk(audio_clk),.audio_rst_n(rst_n), \
 .audio_snapshot(snapshot),.audio_game_snapshot(game_snapshot),.audio_pcm_valid(pcm_valid), \
 .audio_pcm(pcm),.page(page),.touch_ready(1'b1),.transition(1'b0),.ui_game_snapshot()
guitar_touch_game_display dut(.overlay_valid(5'd0),.overlay_data(480'd0),.frame_begin(),`DISPLAY_INPUTS,.lcd_pclk(p),.lcd_hsync(h),.lcd_vsync(v),
 .lcd_de(d),.lcd_backlight(l),.lcd_r(r),.lcd_g(g),.lcd_b(b));
frozen_guitar_touch_game_display reference(`DISPLAY_INPUTS,.lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),
 .lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb));
integer tick=0,sample=0,frames=0,pixels=0,passes=0,updates=0,min_blank=1000000,age=1000000;
integer i;
reg [639:0] visible_bars;
reg [31:0] visible_gain;
reg was_active=0;
always @(negedge audio_clk)if(rst_n)begin
 pcm_valid=0;
 if(tick==255)begin
  tick=0;sample=sample+1;pcm_valid=1;
  pcm=$rtoi((frames<4 ? 2000000.0 : frames<7 ? 500000.0 : 0.0)*
     ($sin(sample*0.0575958653)+0.4*$sin(sample*0.1151917306)));
  for(i=0;i<4;i=i+1)snapshot[i*32+:32]=sample*(32'd19685267+i*32'd4123000);
  snapshot[287:256]=sample*32'd19685267;
 end else tick=tick+1;
end
always @(posedge clk)begin
 #2;
 if(rst_n && dut.initialized)begin
  if({p,h,v,d,l,r,g,b}!=={rp,rh,rv,rd,rl,rr,rg,rb})
   $fatal(1,"FAIL: frozen display scan/RGB frame=%0d x=%0d y=%0d",frames,dut.x,dut.y);
  if(dut.renderer_deadline_miss || dut.chart_deadline || dut.chart_overflow || dut.pcm_overrun)
   $fatal(1,"FAIL: integrated display deadline/overrun");
  if(dut.targets!==reference.targets || dut.curve_active!==reference.curve_active ||
     dut.u_palette.curve_gain!==reference.u_palette.curve_gain)
   $fatal(1,"FAIL: FFT targets or curve fade differs");
  if(dut.bands_update)updates=updates+1;
  if(dut.visual_update)begin
   if(dut.active || dut.u_palette.bar_busy)$fatal(1,"FAIL: palette update outside blank or overlap");
   age=0;passes=passes+1;
  end else age=age+1;
  if(dut.active)begin
   if(dut.u_palette.bar_busy)$fatal(1,"FAIL: palette missed active video deadline");
   if(!was_active && dut.y==0)begin
    if(age<min_blank)min_blank=age;
    for(integer j=0;j<64;j=j+1)begin
     visible_bars[j*10+:10]={dut.u_palette.heights[j],dut.u_palette.peaks[j]};
     if(dut.u_palette.heights[j]!==reference.u_palette.heights[j] ||
        dut.u_palette.peaks[j]!==reference.u_palette.peaks[j])
      $fatal(1,"FAIL: visible spectrum state differs");
    end
    visible_gain=dut.u_palette.curve_gain;
   end
   for(integer j=0;j<64;j=j+1)
    if(visible_bars[j*10+:10]!=={dut.u_palette.heights[j],dut.u_palette.peaks[j]})
     $fatal(1,"FAIL: spectrum tears in active frame");
   if(visible_gain!==dut.u_palette.curve_gain)$fatal(1,"FAIL: fade tears in active frame");
  end
  was_active=dut.active;
  if(dut.frame_start)begin
   frames=frames+1;
   case(frames)
    1:begin snapshot[335:332]=15;snapshot[367:352]=16'hffff;snapshot[399:368]=32'h01010101;end
    3:begin snapshot[367:352]=16'h3210;end
    4:begin snapshot[335:332]=0;snapshot[367:352]=0;page=0;end
    5:page=5;
    6:begin page=1;game_snapshot[159:128]=48000;end
    13:begin
     if(dut.curve_active!=0)$fatal(1,"FAIL: eight-frame curve tail not finished");
     snapshot[335:332]=1;snapshot[367:352]=15;snapshot[375:368]=2;
    end
    14:page=6;
    15:page=1;
   endcase
  end
 end
end
always @(posedge p)if(d)begin
 pixels=pixels+1;
 if(pixels==480*272*15)begin
  if(updates<8 || passes<15 || min_blank<64)$fatal(1,"FAIL: missing dynamic FFT/blank coverage");
  $display("PASS: P1 integrated frozen display %0d active pixels / 15 frames; %0d real FFT updates, %0d visual passes, minimum update-to-active %0d clocks; fade, peak decay, page changes and six-clock scan identical",pixels,updates,passes,min_blank);
  $finish;
 end
end
initial begin
 for(integer j=0;j<4;j=j+1)begin
  snapshot[128+j*32+:32]=32'd19685267+j*32'd4123000;
  snapshot[288+j*11+:11]=220+j*55;
 end
 #1000;rst_n=1;
end
initial begin #400000000;$fatal(1,"FAIL: integrated display watchdog");end
endmodule
