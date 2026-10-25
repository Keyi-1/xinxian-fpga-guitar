`timescale 1ns/1ps
module tb_vibrato_scan_timing;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;wire [8:0] x,y,bx,by;
    wire [23:0] pins,bpins;wire active,bactive,frame,bframe;
    wire [17:0] pixel={x[5:0],y[5:0],x[5:0]^y[5:0]};
    wire [17:0] bpixel={bx[5:0],by[5:0],bx[5:0]^by[5:0]};
    integer clocks=0,visible=0,frames=0;
`define PORTS .clk(clk),.rst_n(rst_n)
`define OUTPUTS(a,b) .pixel_x(a``x),.pixel_y(a``y),.pixel_active(a``active),.frame_start(a``frame), \
    .lcd_pclk(b[23]),.lcd_hsync(b[22]),.lcd_vsync(b[21]),.lcd_de(b[20]), \
    .lcd_r(b[17:12]),.lcd_g(b[11:6]),.lcd_b(b[5:0])
    lcd_rgb_scan_480x272 dut(`PORTS,.pixel_rgb(pixel),`OUTPUTS(,pins));
    vibrato_before_lcd_rgb_scan_480x272 frozen(`PORTS,.pixel_rgb(bpixel),`OUTPUTS(b,bpins));
`undef PORTS
`undef OUTPUTS
    always @(posedge clk)begin
        #1;
        if({x,y,active,frame,pins[23:20],pins[17:0]} !== {bx,by,bactive,bframe,bpins[23:20],bpins[17:0]})
            $fatal(1,"FAIL: registered y changes scan coordinate/mask/RGB/DCLK clock%0d",clocks);
        if(y!==9'(dut.v_count-12))$fatal(1,"FAIL: y != (v_count-12) modulo512");
        clocks=clocks+1;
        if(active)visible=visible+1;
        if(frame)frames=frames+1;
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(1900000)@(negedge clk);
        rst_n=0;repeat(3)@(negedge clk);rst_n=1;
        repeat(17041)@(negedge clk);rst_n=0;
        repeat(2)@(negedge clk);rst_n=1;repeat(100)@(negedge clk);
        if(frames<2 || visible<1566720)$fatal(1,"FAIL: insufficient complete scan coverage");
        $display("PASS: frozen scan %0d clocks/%0d active-clock samples/%0d frames, exact9-bit coordinates/mask/RGB/all scan pins every clock, modulo512/frame wrap/blank/reset, same6 clocks per pixel",clocks,visible,frames);
        $finish;
    end
    initial begin #25000000;$fatal(1,"FAIL: scan timing watchdog");end
endmodule
