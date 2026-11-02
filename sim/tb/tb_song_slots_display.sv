`timescale 1ns/1ps
module tb_song_slots_display;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame=0;reg [2:0] page=2,selected=0,old_selected=0;
    reg [8:0] x=511,y=511,old_y=511;
    reg [4:0] overlay=0;reg [479:0] descriptors=0;
    reg [255:0] snapshot=0,old_snapshot=0;
    wire [17:0] rgb,old_rgb;wire [2:0] shown,old_shown;
    `define PORTS .clk(clk),.rst_n(rst_n),.frame_start(frame),.page(page),.display_fault(1'b0), \
        .overlay_valid(overlay),.overlay_data(descriptors),.touch_ready(1'b1),.transition(1'b0),.x(x), \
        .centres(384'd0),.tails(288'd0),.valid_blocks(32'd0),.imu_status(10'd93)
    touch_game_renderer #(.USE_P2(1),.WRITABLE(1),.IMU_ENABLE(1)) dut(`PORTS,.selected_slot(selected),.y(y),.game_snapshot(snapshot),.rgb(rgb),.display_page(shown));
    frozen_touch_game_renderer #(.USE_P2(1),.WRITABLE(1),.IMU_ENABLE(1)) accepted(`PORTS,.selected_slot(old_selected),.y(old_y),.game_snapshot(old_snapshot),.rgb(old_rgb),.display_page(old_shown));
    `undef PORTS
    integer scene,px,py,pixels=0,ppm=0,s;
    function integer legacy(input integer n);legacy=n==1 ? 2 : n==2 ? 3 : n;endfunction
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(s=0;s<5;s=s+1)descriptors[s*96+:32]=100;
        for(scene=0;scene<15;scene=scene+1)begin
            overlay=0;page=scene<6 ? 2 : scene<9 ? 3 : scene<12 ? 5 : 6;
            selected=scene<6 ? 0 : (scene-6)%3;old_selected=legacy(selected);
            snapshot=0;snapshot[237:235]=selected;snapshot[229:228]=2;snapshot[127:96]=1234;
            if(page==5)snapshot[95:64]=selected==0 ? 810000 : selected==1 ? 4608000 : 3648000;
            old_snapshot=snapshot;old_snapshot[237:235]=old_selected;
            if(scene>0 && scene<6)overlay=1<<(scene-1);
            @(negedge clk);x=511;y=511;old_y=511;frame=1;@(negedge clk);frame=0;repeat(600)@(negedge clk);
            if(scene==0)begin ppm=$fopen("song_slots_123.ppm","w");$fwrite(ppm,"P3\n480 272\n63\n");end
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;old_y=py;
                if(scene==0)old_y=py>=92 && py<180 ? py+44 : py>=180 && py<224 ? py-88 : py>=224 && py<268 ? py-132 : py;
                repeat(6)@(posedge clk);#1;
                // Imported USERn rows retain their own n and RAM labels.
                if((scene==0 || scene>=6 || (py>=48+(scene-1)*44 && py<92+(scene-1)*44)) && rgb!==old_rgb)
                    $fatal(1,"FAIL: reordered/baseline pixel scene%0d x%0d y%0d rgb%h old%h",scene,px,py,rgb,old_rgb);
                if(shown!==old_shown)$fatal(1,"FAIL: page timing");
                if(ppm)$fwrite(ppm,"%0d %0d %0d\n",rgb[17:12],rgb[11:6],rgb[5:0]);
                pixels=pixels+1;
            end
            if(ppm)begin $fclose(ppm);ppm=0;end
        end
        $display("PASS: %0d RTL pixels/15 scenes: menu exact row permutation, identical pending labels4/5, each imported USERn row, remapped ready/game/result title/timbre caption/progress",pixels);$finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: slots display watchdog");end
endmodule
