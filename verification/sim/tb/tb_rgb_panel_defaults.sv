`timescale 1ns/1ps
// Independent full-frame oracle for the new, unoverridden spectrum defaults.
module tb_rgb_panel_defaults;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    wire [4:0] bar;
    wire hs,vs,de,frame_start;
    wire [7:0] r,g,b;
    rgb_spectrum_timing dut(.pixel_clk(clk),.rst_n(rst_n),
        .bar_read_index(bar),.bar_height(9'd100),.peak_height(9'd130),
        .lcd_hsync(hs),.lcd_vsync(vs),.lcd_de(de),
        .lcd_r(r),.lcd_g(g),.lcd_b(b),.frame_start(frame_start),.pixel_x(),.pixel_y());
    integer i,h,v,visible=0;
    reg [23:0] expected;
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        for(i=0;i<531*292;i++) begin
            if(i>0) @(negedge clk);
            h=i%531; v=i/531;
            if(de !== (h<480 && v<272)) $fatal(1,"FAIL: default active area");
            if(hs !== !(h>=488 && h<492)) $fatal(1,"FAIL: default HSYNC");
            if(vs !== !(v>=280 && v<284)) $fatal(1,"FAIL: default VSYNC");
            expected=0;
            if(h<480 && v<272) begin
                visible++;
                if(bar!=h/15) $fatal(1,"FAIL: 32 spectrum slots do not span 480 pixels");
                if(h%15<12) begin
                    if(v>=172) expected=24'h00c0ff;
                    else if(v==141 || v==142) expected=24'hffd020;
                end
            end
            if({r,g,b}!==expected) $fatal(1,"FAIL: default spectrum pixel (%0d,%0d)",h,v);
        end
        @(negedge clk);
        if(!frame_start || visible!=130560) $fatal(1,"FAIL: default frame period/totals");
        $display("PASS: default 480x272 spectrum, 531x292 totals, 32 bars, porch/sync and all 130560 pixels");
        $finish;
    end
    initial begin #4000000; $fatal(1,"FAIL: default spectrum timeout"); end
endmodule
