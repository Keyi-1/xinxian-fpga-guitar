`timescale 1ns/1ps
// Pixel-edge checks and exhaustive native pixels, plus portrait/scaled input.
module tb_touch_rotation_mapper;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame=0;
    reg [3:0] count=1;reg [7:0] id=7;
    reg [15:0] raw_x=0,raw_y=0,max_x=480,max_y=272;
    wire a_valid,b_valid,c_valid;
    wire [3:0] an,bn,cn;wire [7:0] ai,bi,ci;
    wire [8:0] ax,ay,bx,by,cx,cy;
    `define PORTS .clk(clk),.rst_n(rst_n),.frame_valid(frame),.count(count),.track_id(id), \
        .raw_x(raw_x),.raw_y(raw_y),.max_x(max_x),.max_y(max_y)
    touch_coordinate_mapper original(`PORTS,.valid(a_valid),.mapped_count(an),.mapped_id(ai),.x(ax),.y(ay));
    touch_coordinate_mapper #(.MIRROR_X(1),.MIRROR_Y(1)) rotated(`PORTS,.valid(b_valid),.mapped_count(bn),.mapped_id(bi),.x(bx),.y(by));
    // A panel's own X mirror composes with rotation: (1 XOR1,0 XOR1).
    touch_coordinate_mapper #(.MIRROR_X(0),.MIRROR_Y(1)) calibrated(`PORTS,.valid(c_valid),.mapped_count(cn),.mapped_id(ci),.x(cx),.y(cy));
    `undef PORTS
    integer x,y,cases=0;
    task report(input integer px,py);
        @(negedge clk);raw_x=px;raw_y=py;frame=1;@(negedge clk);frame=0;
        wait(a_valid);#1;
        if(!b_valid || !c_valid || an!==bn || an!==cn || ai!==bi || ai!==ci)
            $fatal(1,"FAIL: timing/count/id changed");
        if(an==1 && (bx!==479-ax || by!==271-ay || cx!==ax || cy!==by))
            $fatal(1,"FAIL: rotation/composition raw=%0d,%0d",px,py);
        cases=cases+1;
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(y=0;y<272;y=y+1)for(x=0;x<480;x=x+1)begin
            report(x,y);if(ax!==x || ay!==y)$fatal(1,"FAIL: native scale");
        end
        max_x=272;max_y=480;
        for(y=0;y<480;y=y+29)for(x=0;x<272;x=x+17)begin
            report(x,y);if(ax!==y || ay!==x)$fatal(1,"FAIL: portrait swap");
        end
        max_x=800;max_y=480;
        for(y=0;y<480;y=y+23)for(x=0;x<800;x=x+37)begin
            report(x,y);if(ax!==x*480/800 || ay!==y*272/480)$fatal(1,"FAIL: scaled input");
        end
        max_x=480;max_y=272;report(480,0);if(an!=15)$fatal(1,"FAIL: range rejection");
        count=2;report(100,100);if(an!=2)$fatal(1,"FAIL: multitouch");
        count=0;report(100,100);if(an!=0)$fatal(1,"FAIL: release");
        $display("PASS: %0d mapper frames, all130560 native pixels, portrait/scaling/mirror composition/range/multitouch/release",cases);$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: touch mapper watchdog");end
endmodule
