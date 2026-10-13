`timescale 1ns/1ps
module tb_guitar_curve_fade;
    reg clk=0,rst_n=0,update=0;
    always #10 clk=~clk;
    reg [3:0] active=0;
    reg [15:0] level=0;
    reg [31:0] strikes=0;
    reg [11:0] mask=7;
    wire [17:0] rgb;
    wire [3:0] visible;
    guitar_radial_palette dut(.clk(clk),.rst_n(rst_n),.frame_start(1'b0),.visual_update(update),
        .x(9'd345),.y(9'd137),.mask(mask),.voice_active(active),.flash(4'd0),
        .hz(44'd0),.fret(16'd0),.level(level),.strikes(strikes),.targets(160'd0),
        .rgb(rgb),.curve_active(visible));
    integer frames=0,trace;
    task automatic frame;
        begin
            @(negedge clk);update=1;@(negedge clk);update=0;
            repeat(8)@(negedge clk);frames++;
            $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",frames,
                active,dut.curve_gain[7:0],dut.curve_gain[15:8],dut.curve_gain[23:16],
                dut.curve_gain[31:24],rgb[17:12],rgb[11:6],rgb[5:0]);
        end
    endtask
    task automatic check_pixel;
        integer r,g,b,peak;
        begin
            r=rgb[17:12]-1;g=rgb[11:6]-2;b=rgb[5:0]-5;
            peak=r>g ? r : g;if(b>peak)peak=b;
            // Background addition saturates at 63; the blue baseline can
            // absorb up to five codes from a full-brightness blue primary.
            if(peak>(dut.curve_gain[7:0]>>2) || peak+5<(dut.curve_gain[7:0]>>2))
                $fatal(1,"FAIL: RGB does not follow fade gain: %0d",peak);
        end
    endtask
    integer i,j,previous,steps=0;
    reg [31:0] before_gain;
    initial begin
        trace=$fopen("radial_curve_gain.csv","w");
        if(!trace)$fatal(1,"FAIL: gain trace output");
        $fwrite(trace,"frame,active,gain0,gain1,gain2,gain3,r,g,b\n");
        repeat(5)@(negedge clk);rst_n=1;frame();
        if(visible!=0 || rgb!={6'd1,6'd2,6'd5})$fatal(1,"FAIL: startup phantom curve");
        // Independent pluck attacks; 4-bit peak levels are intentionally coarse.
        active=15;level=16'hffff;strikes=32'h01010101;frame();
        if(dut.curve_gain!=32'hffffffff || visible!=15)$fatal(1,"FAIL: four-voice immediate attack");
        repeat(16)frame();
        previous=dut.curve_gain[7:0];check_pixel();
        for(i=14;i>=0;i--)begin
            level[3:0]=i;
            repeat(8)begin
                frame();check_pixel();
                if(dut.curve_gain[7:0]>previous || dut.curve_gain[7:0]<i*16)
                    $fatal(1,"FAIL: peak release is not smooth and bounded");
                if(dut.curve_gain[7:0]<previous)steps++;
                previous=dut.curve_gain[7:0];
                for(j=1;j<4;j++)if(dut.curve_gain[j*8+:8]<240)
                    $fatal(1,"FAIL: one voice fading dims another voice");
            end
        end
        if(steps<80 || previous>=100)$fatal(1,"FAIL: curve retains a brightness floor");
        // At voice end there must be an actual tail, then exact zero/background.
        active[0]=0;previous=dut.curve_gain[7:0];
        frame();check_pixel();
        if(!visible[0] || dut.curve_gain[7:0]==0 || dut.curve_gain[7:0]>=previous)
            $fatal(1,"FAIL: abrupt disappearance at voice end");
        repeat(7)begin frame();check_pixel();end
        if(dut.curve_gain[7:0]!=0 || visible[0] || rgb!={6'd1,6'd2,6'd5})
            $fatal(1,"FAIL: tail has not reached zero after eight frames");
        level[3:0]=15;active[0]=1;strikes[7:0]++;frame();
        if(dut.curve_gain[7:0]!=255)$fatal(1,"FAIL: fresh pluck does not restore full brightness");
        active=0;frame();frame();
        if(visible!=15)$fatal(1,"FAIL: four concurrent display tails removed");
        strikes[23:16]++;active[2]=1;frame();
        if(dut.curve_gain[23:16]!=255 || dut.curve_gain[7:0]>=224)
            $fatal(1,"FAIL: retrigger must only reset its own tail");
        repeat(20)frame();
        if(visible!=4 || dut.curve_gain[31:24]!=0)$fatal(1,"FAIL: inactive tails persist");
        before_gain=dut.curve_gain;
        repeat(200)@(negedge clk);
        if(dut.curve_gain!=before_gain)$fatal(1,"FAIL: gain changed inside a frame");
        // Coarse level zero while active must also fade all the way to black.
        level=0;repeat(180)frame();
        if(visible!=0 || dut.curve_gain!=0)$fatal(1,"FAIL: active silent voice retains brightness");
        // The 8-bit event counter wraps without losing the next pluck.
        strikes[7:0]=255;active=1;frame();strikes[7:0]=0;frame();
        if(dut.curve_gain[7:0]!=255 || !visible[0])$fatal(1,"FAIL: strike wrap lost");
        rst_n=0;repeat(8)@(negedge clk);
        if(dut.curve_gain!=0 || visible!=0)$fatal(1,"FAIL: reset tail");
        $fclose(trace);
        $display("PASS: four independent 8-bit curve gains; %0d gradual release steps; zero brightness floor; eight-frame tail; isolated retrigger/wrap; frame-stable RGB and reset",steps);
        $finish;
    end
    initial begin #2000000;$fatal(1,"FAIL: fade test timeout");end
endmodule
