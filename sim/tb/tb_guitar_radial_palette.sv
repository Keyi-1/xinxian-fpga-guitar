`timescale 1ns/1ps
module tb_guitar_radial_palette;
    reg clk=0,rst=0,update=0;
    always #10 clk=~clk;
    reg [8:0] x=0,y=0;
    reg [31:0] strikes=0;
    reg [159:0] targets=0;
    wire [17:0] rgb;
    guitar_radial_palette dut(.clk(clk),.rst_n(rst),.frame_start(1'b0),.visual_update(update),
        .x(x),.y(y),.mask(12'd0),.voice_active(4'd0),.flash(4'd0),.hz(44'd0),
        .fret(16'd0),.level(16'd0),.strikes(strikes),.targets(targets),.rgb(rgb),.curve_active());
    task automatic tick;
        begin @(negedge clk);update=1;@(negedge clk);update=0;end
    endtask
    integer i,j,xx,yy,expected,error,checked=0;
    real angle;
    initial begin
        repeat(5)@(negedge clk);rst=1;tick();
        for(i=0;i<4;i++)if(dut.envelope[i]!=0)$fatal(1,"FAIL: no pluck lights strip");
        for(i=0;i<4;i++)begin
            strikes[i*8+:8]=1;tick();
            if(dut.envelope[i]!=31)$fatal(1,"FAIL: accepted pluck attack");
        end
        repeat(33)tick();
        for(i=0;i<4;i++)if(dut.envelope[i]!=0)$fatal(1,"FAIL: strip does not fade");
        strikes=32'h02020202;tick();
        for(i=0;i<4;i++)if(dut.envelope[i]!=31)$fatal(1,"FAIL: four concurrent strips");
        for(i=0;i<32;i++)targets[i*5+:5]=27;
        repeat(8)tick();
        for(i=0;i<64;i++)if(dut.heights[i]!=27)$fatal(1,"FAIL: spectrum attack %0d",i);
        targets=0;repeat(28)tick();
        for(i=0;i<64;i++)if(dut.heights[i]!=0)$fatal(1,"FAIL: silence holds artificial bars");
        for(yy=0;yy<272;yy++)for(xx=208;xx<480;xx++)begin
            @(negedge clk);x=xx;y=yy;repeat(6)@(negedge clk);
            if(dut.squared4!=(2*xx-687)**2+(2*yy-271)**2)$fatal(1,"FAIL: half-pixel circular geometry");
            if(dut.squared4>=44521)begin
                angle=$atan2(2.0*xx-687,271.0-2.0*yy);
                if(angle<0)angle+=2.0*3.141592653589793;
                expected=$rtoi(angle*64/(2.0*3.141592653589793));
                error=expected-dut.angle4;if(error<0)error=-error;
                if(error>1 && error<63)$fatal(1,"FAIL: clockwise polar index at %0d,%0d got=%0d expected=%0d",xx,yy,dut.angle4,expected);
                checked++;
            end
            if($isunknown(rgb))$fatal(1,"FAIL: unknown radial RGB");
        end
        $display("PASS: %0d circular pixels independent atan2/squared-distance oracle, clockwise 64 sectors; pluck-only four-strip attack/fade; spectrum rise/silence",checked);$finish;
    end
endmodule
