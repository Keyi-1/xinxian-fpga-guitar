`timescale 1ns/1ps
`include "game_score_config.vh"
module tb_game_chart_renderer;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_start=0,snapshot_update=0;
    reg [255:0] snapshot=0;
    wire [383:0] centres;wire [287:0] tails;wire [31:0] blocks;
    wire [255:0] displayed;wire overflow,deadline;
    reg [2:0] page=0;reg [8:0] x=0,y=0;
    wire [17:0] rgb;wire [2:0] displayed_page;
    game_chart_layout chart(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.snapshot_update(snapshot_update),
        .snapshot(snapshot),.centres(centres),.tails(tails),.valid_blocks(blocks),.display_snapshot(displayed),
        .overflow(overflow),.deadline_miss(deadline));
    touch_game_renderer renderer(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.page(page),
        .touch_ready(1'b1),.transition(1'b0),.x(x),.y(y),.centres(centres),.tails(tails),
        .valid_blocks(blocks),.game_snapshot(displayed),.rgb(rgb),.display_page(displayed_page));
    integer clocks,counts[0:3],i,l,slot,delta,expected,now,fd,px,py;
    reg [79:0] event_word;
    task publish(input integer t);
        @(negedge clk);snapshot[159:128]=t;frame_start=1;
        @(negedge clk);frame_start=0;snapshot_update=1;
        @(negedge clk);snapshot_update=0;clocks=0;
        wait(chart.state==1);
        while(chart.state!=0)begin @(negedge clk);clocks=clocks+1;end
        if(clocks>=38200 || deadline || overflow)$fatal(1,"FAIL: chart blank budget/overflow");
        for(l=0;l<4;l=l+1)counts[l]=0;
        for(i=0;i<`GAME_EVENT_COUNT;i=i+1)begin
            event_word=chart.u_rom.memory[i];delta=int'(event_word[23:0])-t;l=event_word[75:74];
            if(!snapshot[i] && delta<=101000 && delta>=-7200)begin
                slot=l*8+counts[l];counts[l]=counts[l]+1;
                expected=96+(delta<0 ? -((-delta+125)/250) : (delta+125)/250);
                if(!blocks[slot] || centres[slot*12+:12]!=expected)
                    $fatal(1,"FAIL: chart position t=%0d event=%0d x=%0d expected=%0d",t,i,centres[slot*12+:12],expected);
            end
        end
        for(l=0;l<4;l=l+1)for(i=counts[l];i<8;i=i+1)
            if(blocks[l*8+i])$fatal(1,"FAIL: stale block");
    endtask
    task picture(input integer p,input string filename);
        page=p;publish(24000);repeat(30)@(negedge clk);
        fd=$fopen(filename,"w");$fwrite(fd,"P3\n480 272\n255\n");
        for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
            @(negedge clk);x=px;y=py;repeat(5)@(negedge clk);
            if(^rgb===1'bx)$fatal(1,"FAIL: unknown UI pixel");
            $fwrite(fd,"%0d %0d %0d\n",(rgb[17:12]*255)/63,(rgb[11:6]*255)/63,(rgb[5:0]*255)/63);
        end
        $fclose(fd);
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        // Walk the whole real score, including countdown and signed offsets.
        for(now=-96000;now<=`GAME_DURATION_SAMPLES;now=now+4800)publish(now);
        publish(0);publish(125);publish(-125);
        picture(0,"touch_home.ppm");picture(2,"touch_songs.ppm");picture(3,"touch_ready.ppm");
        snapshot[179:160]=1270;snapshot[187:180]=12;snapshot[195:188]=18;snapshot[203:196]=23;
        snapshot[222:220]=1;picture(5,"touch_game.ppm");picture(6,"touch_result.ppm");
        $display("PASS: full-score chart positions/blank deadline/capacity and five RTL pixel previews");$finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: chart/render watchdog");end
endmodule
