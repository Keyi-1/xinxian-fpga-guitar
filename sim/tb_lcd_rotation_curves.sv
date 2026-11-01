`timescale 1ns/1ps
module tb_lcd_rotation_curves;
    reg clk=0,rst_n=0,start=0;
    always #10 clk=~clk;
    reg [399:0] snapshot=0;
    reg [3:0] draw_voices=0;
    reg [8:0] x=9,y=283;
    wire initialized,miss;
    wire [11:0] mask;
    guitar_radial_curve_renderer #(.ROTATE_180(1)) dut(.clk(clk),.rst_n(rst_n),.frame_start(start),.snapshot(snapshot),
        .curve_active(draw_voices),
        .pixel_x(x),.pixel_y(y),.pixel_active(1'b0),.initialized(initialized),.mask(mask),
        .display_hz(),.display_fret(),.display_level(),.display_active(),.display_flash(),.deadline_miss(miss),.visual_update(),.display_strikes());
    integer max_cycles=0,lines=0;
    real pi=3.141592653589793;
    task automatic render_frame(input reg [3:0] voices,input reg [3:0] curves);
        integer row,cycles,px,v,k,side,expected_x,nearby,total,found;
        real theta,refphase,dt,ratio,phase,xx;
        reg [11:0] actual,near_pixel;
        begin
            snapshot[335:332]=voices;
            draw_voices=curves;
            x=9;y=283;
            @(negedge clk);start=1;@(negedge clk);start=0;
            wait(dut.state==1);#1;
            for(v=0;v<4;v++)
                if(dut.ratios[v] != ({16'd0,snapshot[128+v*32+:32]}<<16)/19685267)
                    $fatal(1,"FAIL: shared frequency divider voice %0d",v);
            for(row=271;row>=0;row--)begin
                @(negedge clk);y=row+1;x=10;
                @(negedge clk);x=9;cycles=1;
                while(dut.state!=1)begin @(negedge clk);cycles++;end
                if(cycles>max_cycles)max_cycles=cycles;
                if(cycles>=3186 || miss)$fatal(1,"FAIL: row %0d missed 3186-clock budget (%0d)",row,cycles);
                total=0;
                for(px=0;px<512;px++)begin
                    actual=dut.front_bank ? dut.u_bank0.pixels[px] : dut.u_bank1.pixels[px];
                    if($isunknown(actual))$fatal(1,"FAIL: unknown scanline coverage");
                    if(actual!=0)begin
                        total++;
                        if(px<266 || px>422 || row<61 || row>210)
                            $fatal(1,"FAIL: curve escapes centered square at %0d,%0d",px,row);
                    end
                    for(v=0;v<4;v++)if(!curves[v] && actual[v*3+:3]!=0)
                        $fatal(1,"FAIL: stopped voice visible");
                end
                // Independent analytic oracle: every sine/reference crossing
                // must meet the core within two pixels (ROM/AA quantization).
                if(row>=61 && row<=210)begin
                    theta=$asin((row-135.5)/74.5)/(2*pi);
                    refphase=$itor(snapshot[287:272])/65536.0;
                    for(v=0;v<4;v++)if(curves[v])begin
                        ratio=$itor(snapshot[128+v*32+:32])/19685267.0;
                        phase=$itor(snapshot[v*32+16+:16])/65536.0;
                        for(k=0;k<6;k++)for(side=0;side<2;side++)begin
                            dt=k+(side==0 ? theta : 0.5-theta)-refphase;
                            if(dt>=0 && dt<1024.0*220.0/48000.0)begin
                                xx=343.5+74.5*$sin(2*pi*(phase+ratio*dt));expected_x=$rtoi(xx+0.5);found=0;
                                for(nearby=expected_x-2;nearby<=expected_x+2;nearby++)begin
                                    near_pixel=dut.front_bank ? dut.u_bank0.pixels[nearby] : dut.u_bank1.pixels[nearby];
                                    if(near_pixel[v*3+:3]>=2)found=1;
                                end
                                if(!found)$fatal(1,"FAIL: analytic crossing voice=%0d row=%0d x=%0d",v,row,expected_x);
                            end
                        end
                    end
                end
                if(curves==0 && total!=0)$fatal(1,"FAIL: zero gain paints a curve");
                // Repeated h=512 event during vertical blank must be ignored.
                @(negedge clk);x=10;@(negedge clk);x=9;
                if(dut.state!=1 || miss)$fatal(1,"FAIL: duplicate row trigger");
                lines++;
            end
            $display("PASS: native centered square active=%b curves=%b analytic crossings, coverage, no dropped rows",voices,curves);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;wait(initialized);
        snapshot[351:336]=16'h8753;snapshot[367:352]=16'hc864;
        snapshot[255:128]={32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F};
        render_frame(0,0);render_frame(1,1);
        snapshot[127:0]={32'hf1234567,32'h789abcde,32'h2468abcd,32'h12345678};
        snapshot[287:256]=32'h13579bdf;render_frame(15,15);
        // All four highest frets; multiple phases stress near-horizontal turns.
        snapshot[255:128]={32'h013E3C06,32'h01A8CAC3,32'h02173456,32'h02CA6987};
        render_frame(15,15);
        snapshot[127:0]=snapshot[127:0]+128'h11111111444444447777777799999999;
        snapshot[287:256]=32'hc56789ab;render_frame(15,15);render_frame(14,14);
        // Voice lifecycle and visible tails are independent. Even with all
        // audio voices inactive, the same analytic geometry must remain.
        render_frame(0,15);render_frame(0,0);
        $display("PASS: 180 degree musical scanline renderer %0d lines, worst %0d/3186 clocks, native pixels, antialias/ghost/shared arithmetic",lines,max_cycles);
        $finish;
    end
    initial begin #60000000;$fatal(1,"FAIL: renderer timeout");end
endmodule
