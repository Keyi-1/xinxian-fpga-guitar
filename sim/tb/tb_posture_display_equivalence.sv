`timescale 1ns/1ps
module tb_posture_display_equivalence;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame=0;reg [2:0] page=0;
    reg [8:0] x=511,y=511;reg [9:0] status=0,held_status=0;
    reg [255:0] snapshot=0;wire [17:0] rgb,old_rgb;wire [2:0] shown,old_shown;
    integer scene,px,py,pixels=0,changed=0,ppm=0;
    touch_game_renderer #(.USE_P2(1),.WRITABLE(1),.IMU_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.frame_start(frame),.page(page),.selected_slot(3'd3),.display_fault(1'b0),
        .overlay_valid(5'd0),.overlay_data(480'd0),.touch_ready(1'b1),.transition(1'b0),.x(x),.y(y),
        .centres(384'd0),.tails(288'd0),.valid_blocks(32'd0),.game_snapshot(snapshot),.imu_status(status),.rgb(rgb),.display_page(shown));
    posture_frozen_renderer #(.USE_P2(1),.WRITABLE(1)) frozen(
        .clk(clk),.rst_n(rst_n),.frame_start(frame),.page(page),.selected_slot(3'd3),.display_fault(1'b0),
        .overlay_valid(5'd0),.overlay_data(480'd0),.touch_ready(1'b1),.transition(1'b0),.x(x),.y(y),
        .centres(384'd0),.tails(288'd0),.valid_blocks(32'd0),.game_snapshot(snapshot),.rgb(old_rgb),.display_page(old_shown));
    reg exception_pixel;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        snapshot[237:235]=3;snapshot[229:228]=2;snapshot[127:96]=1234;
        for(scene=0;scene<12;scene=scene+1)begin
            page=scene<5 ? 0 : scene<7 ? 1 : scene-5;
            status=scene==0 ? 0 : scene==1 ? 1 : scene==2 ? 3 : scene==3 ? 10'd93 : scene==4 ? 10'd637 : scene==5 ? 10'd93 : 10'd221;
            held_status=status;
            @(negedge clk);x=511;y=511;frame=1;@(negedge clk);frame=0;repeat(400)@(negedge clk);
            if(scene==0 || scene==3 || scene==6)begin
                ppm=$fopen(scene==0 ? "posture_home_offline.ppm" : scene==3 ? "posture_home_auto.ppm" : "posture_performance_pending.ppm","w");
                $fwrite(ppm,"P3\n480 272\n63\n");
            end
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;
                if(py==100 && px==0)status=~status; // Must not change active-frame UI state.
                repeat(6)@(posedge clk);#1;
                if(dut.imu_display!==held_status)$fatal(1,"FAIL: IMU status tears inside frame");
                exception_pixel=page==0 && py>=240 && ((px>=16 && px<144)||(px>=160 && px<288)||(px>=328 && px<424)) ||
                    page==1 && py>=256 && px>=384;
                if(shown!==old_shown || (!exception_pixel && rgb!==old_rgb))$fatal(1,"FAIL: unexpected P4 pixel scene%0d page%0d x%0d y%0d",scene,page,px,py);
                if(rgb!==old_rgb)changed=changed+1;
                if(ppm)$fwrite(ppm,"%0d %0d %0d\n",rgb[17:12],rgb[11:6],rgb[5:0]);
                pixels=pixels+1;
            end
            if(ppm)begin $fclose(ppm);ppm=0;end
        end
        if(changed<1000)$fatal(1,"FAIL: missing IMU controls/status text");
        $display("PASS: frozen P3 %0d pixels/12 scenes, exact outside explicit home controls/performance footer, frame-held status, same six clocks/pixel; %0d intentional changed pixels",pixels,changed);$finish;
    end
    initial begin #150000000;$fatal(1,"FAIL: posture display watchdog");end
endmodule
