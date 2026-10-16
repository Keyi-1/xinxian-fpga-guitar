`timescale 1ns/1ps
module tb_game_p2_display;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ac=0;always #10 clk=~clk;always #41 ac=~ac;
    reg rst=0,frame=0,update=0;
    reg [255:0] snapshot=0;
    wire read;wire [10:0] address;wire [95:0] data;
    wire [383:0] centres;wire [287:0] tails;wire [31:0] blocks;
    wire overflow,deadline;reg [2:0] page=5,selected=0;reg [8:0] x=0,y=0;
    wire [17:0] rgb;wire [2:0] shown;
    reg [95:0] words[0:2047];
    integer bases[0:4],counts[0:4],durations[0:4];
    integer ink[0:3];
    integer lane_counts[0:3],s,e,j,head,now,clocks,delta,center,tail,lane,idx,passes=0,max_clocks=0,px,py,fd;
    reg [31:0] expected_blocks;reg [383:0] expected_centres;reg [287:0] expected_tails;
    game_p2_score_bank bank(.audio_clk(ac),.audio_read(1'b1),.audio_address(address),.audio_data(),
        .display_clk(clk),.display_read(read),.display_address(address),.display_data(data));
    game_p2_chart_layout layout(.clk(clk),.rst_n(rst),.frame_start(frame),.snapshot_update(update),.snapshot(snapshot),
        .score_read(read),.score_address(address),.score_data(data),.centres(centres),.tails(tails),.valid_blocks(blocks),
        .display_snapshot(),.overflow(overflow),.deadline_miss(deadline));
    touch_game_renderer #(.USE_P2(1)) renderer(.clk(clk),.rst_n(rst),.frame_start(frame),.page(page),
        .selected_slot(selected),.display_fault(overflow|deadline),.touch_ready(1'b1),.transition(1'b0),
        .x(x),.y(y),.centres(centres),.tails(tails),.valid_blocks(blocks),.game_snapshot(snapshot),.rgb(rgb),.display_page(shown));
    task publish(input integer song,time_value,first,input [63:0] consumed);
        @(negedge clk);snapshot=0;snapshot[63:0]=consumed;snapshot[95:64]=time_value;
        snapshot[229:228]=2;snapshot[237:235]=song;snapshot[249:238]=first;snapshot[255:250]=song+1;
        frame=1;@(negedge clk);frame=0;update=1;@(negedge clk);update=0;clocks=0;
        while(layout.state!=0)begin @(negedge clk);clocks=clocks+1;if(clocks>3500)$fatal(1,"FAIL: blank deadline");end
        if(clocks>max_clocks)max_clocks=clocks;
        expected_blocks=0;expected_centres=0;expected_tails=0;
        for(j=0;j<4;j=j+1)lane_counts[j]=0;
        for(j=first;j<counts[song] && j<first+64;j=j+1)begin
            delta=words[bases[song]+j][31:0]-time_value;lane=words[bases[song]+j][72:71];
            if(!consumed[j%64] && delta>=-7200 && delta<=101000)begin
                if(lane_counts[lane]>=8)$fatal(1,"FAIL: fixture density");
                idx=lane*8+lane_counts[lane];lane_counts[lane]=lane_counts[lane]+1;
                center=96+(delta<0 ? -((-delta+125)/250) : (delta+125)/250);
                tail=words[bases[song]+j][63:32]/250;if(tail>320)tail=320;
                expected_blocks[idx]=1;expected_centres[idx*12+:12]=center;expected_tails[idx*9+:9]=tail;
            end
        end
        if(blocks!==expected_blocks || overflow || deadline)$fatal(1,"FAIL: P2 visibility/fault song=%0d time=%0d",song,time_value);
        for(j=0;j<32;j=j+1)if(blocks[j] && (centres[j*12+:12]!==expected_centres[j*12+:12] || tails[j*9+:9]!==expected_tails[j*9+:9]))
            $fatal(1,"FAIL: P2 position/duration song=%0d time=%0d slot=%0d",song,time_value,j);
        if(renderer.progress_step!=(durations[song]+479)/480)$fatal(1,"FAIL: progress/catalog mismatch");
        passes=passes+1;
    endtask
    initial begin
        $readmemh("../../../mem/game_p2_static.mem",words);
        bases[0]=0;bases[1]=67;bases[2]=323;bases[3]=491;bases[4]=703;
        counts[0]=67;counts[1]=256;counts[2]=168;counts[3]=212;counts[4]=256;
        durations[0]=1620000;durations[1]=12288000;durations[2]=9216000;durations[3]=7296000;durations[4]=28800000;
        repeat(8)@(negedge clk);rst=1;
        for(s=0;s<5;s=s+1)begin
            publish(s,-96000,0,0);publish(s,-48000,0,0);
            for(e=0;e<counts[s];e=e+1)begin
                now=words[bases[s]+e][31:0];head=e>2 ? e-2 : 0;
                publish(s,now-7200,head,0);publish(s,now,head,0);
                publish(s,now+7201,head,64'ha55aa55aa55aa55a);
            end
        end
        publish(1,6144000,126,0);repeat(500)@(negedge clk);
        if(renderer.progress_pixels!=240)$fatal(1,"FAIL: long song progress");
        snapshot[127:96]=204800;snapshot[143:128]=2048;snapshot[159:144]=65535;snapshot[175:160]=300;snapshot[191:176]=256;
        repeat(250)@(negedge clk);
        if(renderer.score_bcd!==24'h204800 || renderer.number_bcd!==80'h00256003006553502048)
            $fatal(1,"FAIL: widened score/counters score=%h counts=%h",renderer.score_bcd,renderer.number_bcd);
        // A scaled ASCII label must show all characters, including odd positions.
        // The old font-column mask accidentally selected the blank right half.
        snapshot[237:235]=2;page=5;
        @(negedge clk);frame=1;@(negedge clk);frame=0;
        for(j=0;j<4;j=j+1)ink[j]=0;
        for(py=0;py<32;py=py+1)for(px=16;px<80;px=px+1)begin
            @(negedge clk);x=px;y=py;repeat(5)@(negedge clk);
            if(rgb=={6'd58,6'd62,6'd63})ink[(px-16)/16]=ink[(px-16)/16]+1;
        end
        for(j=0;j<4;j=j+1)if(ink[j]==0)$fatal(1,"FAIL: scaled RIFF title lost character %0d",j);
        // Render a contact sheet's individual screens at the real six-clock pixel cadence.
        for(s=0;s<4;s=s+1)begin
            selected=s;snapshot[237:235]=s;page=3;@(negedge clk);frame=1;@(negedge clk);frame=0;
            fd=$fopen($sformatf("p2_ready_%0d.ppm",s),"w");$fwrite(fd,"P3\n480 272\n63\n");
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;repeat(5)@(negedge clk);
                if(^rgb===1'bx)$fatal(1,"FAIL: unknown UI pixel");
                $fwrite(fd,"%0d %0d %0d\n",rgb[17:12],rgb[11:6],rgb[5:0]);
            end
            $fclose(fd);
        end
        $display("PASS: %0d complete P2 layouts (all events, ring wrap, dynamic consumed, 10 min/32-bit time); max %0d clocks < 38226 blank clocks; six-digit score, 16-bit counters, progress, all four scaled ASCII title glyphs, four ready screens",passes,max_clocks);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: P2 display watchdog");end
endmodule
