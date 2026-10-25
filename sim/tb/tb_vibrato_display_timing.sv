`timescale 1ns/1ps
module tb_vibrato_display_timing;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame=0,transition=0,ready=1,fault=0;
    reg [2:0] page=0,slot=3;reg [8:0] x=511,y=511;
    reg [383:0] centres=0;reg [287:0] tails=0;reg [31:0] valid=0;
    reg [255:0] snapshot=0;reg [9:0] imu=0;
    reg [4:0] overlay_valid=0;reg [479:0] overlay=0;
    wire [17:0] rgb,old_rgb;wire [2:0] shown,old_shown;
`define PORTS .clk(clk),.rst_n(rst_n),.frame_start(frame),.page(page),.selected_slot(slot), \
    .display_fault(fault),.overlay_valid(overlay_valid),.overlay_data(overlay),.touch_ready(ready), \
    .transition(transition),.x(x),.y(y),.centres(centres),.tails(tails),.valid_blocks(valid), \
    .game_snapshot(snapshot),.imu_status(imu)
    touch_game_renderer #(.USE_P2(1),.WRITABLE(1),.IMU_ENABLE(1)) dut(`PORTS,.rgb(rgb),.display_page(shown));
    vibrato_before_touch_game_renderer #(.USE_P2(1),.WRITABLE(1),.IMU_ENABLE(1)) frozen(`PORTS,.rgb(old_rgb),.display_page(old_shown));
`undef PORTS
    integer clocks=0,pixels=0,scene,px,py,i,j,geometry_cases=0;
    reg [31:0] random_state=32'h40cafe13;
    function [31:0] random_next(input [31:0] state);
        reg [31:0] z;
        begin z=state^(state<<13);z=z^(z>>17);random_next=z^(z<<5);end
    endfunction
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            if(dut.tails1!==frozen.tails1)$fatal(1,"FAIL: retimed tail flag differs");
            if({rgb,shown}!=={old_rgb,old_shown})
                $fatal(1,"FAIL: retimed UI pixel scene%0d page%0d x%0d y%0d",scene,page,x,y);
            clocks=clocks+1;
        end
    end
    task layout(input integer pattern);
        begin
            for(i=0;i<32;i=i+1)begin
                random_state=random_next(random_state);
                centres[i*12+:12]=pattern==0 ? 12'd67+i*13 : random_state[11:0];
                random_state=random_next(random_state);
                tails[i*9+:9]=pattern==0 ? 9'd20+i*3 : random_state[8:0];
            end
            random_state=random_next(random_state);valid=pattern==0 ? 32'hffffffff : random_state;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(j=0;j<4;j=j+1)begin
            layout(1);
            for(py=0;py<512;py=py+1)begin
                @(negedge clk);y=py;x=(py*29)&511;geometry_cases=geometry_cases+8;
            end
        end
        for(scene=0;scene<12;scene=scene+1)begin
            @(negedge clk);x=511;y=511;
            page=scene<7 ? scene : scene<10 ? 5 : scene==10 ? 0 : 6;
            slot=scene%5;ready=scene!=1;transition=scene==9;fault=scene==11;
            overlay_valid=scene>=7 ? 5'b10101 : 0;
            imu=scene*53;snapshot=0;snapshot[237:235]=slot;
            snapshot[127:96]=scene*9187;snapshot[143:128]=scene*233;
            snapshot[159:144]=scene*329;snapshot[175:160]=scene*733;snapshot[191:176]=scene*123;
            snapshot[219:208]=12'h4d1;snapshot[227:220]=scene;
            for(i=0;i<5;i=i+1)overlay[i*96+:96]={32'd12000,32'd319,32'd16000};
            layout(scene<8 ? 0 : 1);frame=1;@(negedge clk);frame=0;
            repeat(512)@(negedge clk);
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;
                if(px==0 && py==100)imu=~imu;
                repeat(6)@(posedge clk);#2;pixels=pixels+1;
            end
        end
        $display("PASS: frozen ID70 UI retiming %0d pixels/12 scenes/%0d clocks/%0d geometry stimuli, all512 y/all32 slots/full centre-tail fields, exact tail flags/RGB/page every clock, same6 clocks per pixel",pixels,clocks,geometry_cases);
        $finish;
    end
    initial begin #150000000;$fatal(1,"FAIL: UI timing watchdog");end
endmodule
