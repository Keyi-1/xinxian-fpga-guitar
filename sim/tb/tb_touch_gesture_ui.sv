`timescale 1ns/1ps
module tb_touch_gesture_ui;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_ms=0,frame=0,flush=0;
    reg [3:0] count=0;reg [7:0] id=7;
    reg [15:0] raw_x=0,raw_y=0,max_x=480,max_y=272;
    wire mapped_valid,click,double_click;
    wire [3:0] mapped_count;wire [7:0] mapped_id;wire [8:0] x,y,cx,cy;
    reg ready=1,command_busy=0,command_done=0;
    reg [255:0] game_snapshot=0;
    wire send,ui_flush,transition;wire [1:0] mode;wire [2:0] page;
    touch_coordinate_mapper mapper(.clk(clk),.rst_n(rst_n),.frame_valid(frame),.count(count),.track_id(id),
        .raw_x(raw_x),.raw_y(raw_y),.max_x(max_x),.max_y(max_y),.valid(mapped_valid),.mapped_count(mapped_count),.mapped_id(mapped_id),.x(x),.y(y));
    touch_gesture gesture(.clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.flush(flush|ui_flush),.frame_valid(mapped_valid),
        .count(mapped_count),.track_id(mapped_id),.x(x),.y(y),.click(click),.double_click(double_click),.click_x(cx),.click_y(cy));
    touch_game_ui #(.FALLBACK_MS(20)) ui(.clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.touch_ready(ready),
        .click(click),.double_click(double_click),.click_x(cx),.click_y(cy),.game_snapshot(game_snapshot),
        .command_busy(command_busy),.command_done(command_done),.command_send(send),.command_mode(mode),.page(page),
        .flush_gesture(ui_flush),.transition(transition));
    integer clicks=0,doubles=0,commands=0;
    always @(posedge clk)begin if(click)clicks=clicks+1;if(double_click)doubles=doubles+1;end
    // Model an acknowledged audio switch, rather than directly changing page.
    always @(posedge clk)begin
        command_done<=0;
        if(send)begin commands=commands+1;command_busy<=1;end
        else if(command_busy)begin command_busy<=0;command_done<=1;end
    end
    task report(input [3:0] n,input integer px,py);
        @(negedge clk);count=n;raw_x=px;raw_y=py;frame=1;
        @(negedge clk);frame=0;repeat(60)@(negedge clk);
    endtask
    task milliseconds(input integer n);
        repeat(n)begin @(negedge clk);tick_ms=1;@(negedge clk);tick_ms=0;end
    endtask
    task tap(input integer px,py);
        report(1,px,py);milliseconds(20);report(0,px,py);repeat(10)@(negedge clk);
    endtask
    task check(input bit pass,input string why);if(!pass)$fatal(1,"FAIL: %s page=%0d",why,page);endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        report(1,333,123);check(x==333 && y==123,"native coordinate exact");report(0,333,123);
        max_x=800;max_y=480;report(1,400,240);check(x==240 && y==136,"serial scaling centre");report(0,400,240);
        max_x=272;max_y=480;report(1,136,240);check(x==240 && y==136,"auto portrait swap");report(0,136,240);
        max_x=480;max_y=272;report(1,480,40);check(mapped_count==15,"out-of-range coordinate cancels");report(0,0,0);
        // Coordinate-only probes also reach the gesture/UI path. Start the
        // menu checks from reset rather than inheriting their incidental taps.
        rst_n=0;repeat(5)@(negedge clk);rst_n=1;
        repeat(5)@(negedge clk);clicks=0;doubles=0;
        tap(100,150);check(page==1 && mode==1,"home tap waits for performance acknowledgement");
        milliseconds(100);tap(210,110);milliseconds(100);tap(215,113);
        check(page==0 && doubles==1,"two short nearby taps return home");
        tap(340,150);check(page==2,"song menu");tap(100,110);check(page==2,"empty slot cannot start");
        tap(100,70);check(page==3,"populated Jasmine slot");tap(100,220);check(page==4 && mode==2,"game start command");
        game_snapshot[233:232]=2;game_snapshot[234]=1;repeat(10)@(negedge clk);check(page==4,"audio countdown owns start epoch");
        game_snapshot[234]=0;repeat(10)@(negedge clk);check(page==5,"audio countdown completion");
        game_snapshot[235]=1;repeat(20)@(negedge clk);check(page==6 && mode==0,"end releases audio before result");
        tap(220,230);check(page==2,"result select song");
        ready=0;milliseconds(25);repeat(20)@(negedge clk);check(page==1,"touch failure falls back to playable instrument");
        // Gestures that must not exit or click: long press, drag, multi-touch, ID switch.
        flush=1;@(negedge clk);flush=0;clicks=0;doubles=0;ready=1;
        report(1,100,100);milliseconds(181);report(0,100,100);
        report(1,100,100);report(1,140,100);report(0,140,100);
        report(1,100,100);report(2,100,100);report(0,100,100);
        report(1,100,100);id=8;report(1,100,100);report(0,100,100);
        check(clicks==0 && doubles==0,"invalid gestures are cancelled");
        $display("PASS: coordinate scaling/swap/range, single/double gestures, menu/song/countdown/result and touch-failure fallback");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: UI watchdog");end
endmodule
