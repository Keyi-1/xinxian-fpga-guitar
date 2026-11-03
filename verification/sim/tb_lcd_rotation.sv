`timescale 1ns/1ps
module tb_lcd_rotation;
    reg clk=0,rst_n=0;
    wire [8:0] x,y,rx,ry;
    wire active,rot_active,frame_start,rot_frame;
    wire pclk,hsync,vsync,de,rpclk,rhsync,rvsync,rde;
    wire [5:0] r,g,b,rr,rg,rb;
    reg [17:0] expected;
    reg check_output;
    integer pixels=0;
    always #5 clk=~clk;
    lcd_rgb_scan_480x272 base(.clk(clk),.rst_n(rst_n),.pixel_rgb({x[5:0],y[5:0],6'd0}),
        .pixel_x(x),.pixel_y(y),.pixel_active(active),.frame_start(frame_start),.lcd_pclk(pclk),
        .lcd_hsync(hsync),.lcd_vsync(vsync),.lcd_de(de),.lcd_r(r),.lcd_g(g),.lcd_b(b));
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        #25000000;
        $fatal(1,"timeout");
    end
    lcd_rgb_scan_480x272 #(.ROTATE_180(1)) rotated(.clk(clk),.rst_n(rst_n),
        .pixel_rgb({rx[5:0],ry[5:0],6'd0}),.pixel_x(rx),.pixel_y(ry),
        .pixel_active(rot_active),.frame_start(rot_frame),.lcd_pclk(rpclk),
        .lcd_hsync(rhsync),.lcd_vsync(rvsync),.lcd_de(rde),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb));
    always @(posedge clk) if(rst_n) begin
        if({pclk,hsync,vsync,de,frame_start,active} !==
           {rpclk,rhsync,rvsync,rde,rot_frame,rot_active})
            $fatal(1,"LCD timing changed");
        if(active && (rx !== 9'd479-x || ry !== 9'd271-y))
            $fatal(1,"rotation mismatch raw=(%0d,%0d) rotated=(%0d,%0d)",x,y,rx,ry);
        check_output=base.phase==5;
        expected=active ? {rx[5:0],ry[5:0],6'd0} : 18'd0;
        if(check_output && active) pixels=pixels+1;
        #1;
        if(check_output && {rr,rg,rb} !== expected)
            $fatal(1,"RGB sampling mismatch");
        if(pixels==2*480*272) begin
            $display("PASS: two frames, %0d pixels map to (479-x,271-y); timing and RGB sampling unchanged",pixels);
            $finish;
        end
    end
endmodule
