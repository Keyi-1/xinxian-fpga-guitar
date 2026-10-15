`timescale 1ns/1ps
module tb_game_competition_controls;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,click=0,done=0,command=0;
    reg [8:0] x=0,y=0;reg [1:0] requested=0;
    reg [7:0] divider=0;
    wire tick=divider==255;
    always @(posedge clk)divider<=divider+1'b1;
    wire send,ack,switching;wire [1:0] ui_mode,mode;wire [2:0] page;
    wire [3:0] note_on;wire [255:0] snapshot;
    touch_game_ui #(.ALLOW_AUTOPLAY_PREVIEW(0)) ui(.clk(clk),.rst_n(rst_n),.tick_ms(1'b0),
        .touch_ready(1'b1),.click(click),.double_click(1'b0),.click_x(x),.click_y(y),.game_snapshot(256'd0),
        .command_busy(1'b0),.command_done(done),.command_send(send),.command_mode(ui_mode),.page(page),
        .flush_gesture(),.transition());
    audio_mode_router #(.COUNTDOWN_SAMPLES(0),.ALLOW_AUTOPLAY_PREVIEW(0)) router(.clk(clk),.rst_n(rst_n),
        .sample_tick(tick),.command_valid(command),.command_mode(requested),.command_ack(ack),.mode(mode),
        .switching(switching),.stable_valid(1'b0),.fret_id(16'd0),.pluck_valid(4'd0),.velocity(8'd0),
        .voice_active(4'd0),.audible_phase(128'd0),.note_on(note_on),.note_off(),.force_release(),
        .target_phase(),.note_velocity(),.game_snapshot(snapshot),.miss_event());
    task tap(input integer tx,ty);
        @(negedge clk);x=tx;y=ty;click=1;@(negedge clk);click=0;repeat(2)@(negedge clk);
    endtask
    task choose(input [1:0] value);
        @(negedge clk);requested=value;command=1;wait(ack);@(negedge clk);command=0;
        repeat(4)@(negedge clk);
    endtask
    always @(posedge clk)if(rst_n && note_on!=0)$fatal(1,"FAIL: strict build started a musical voice without plucking");
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        tap(350,150);tap(200,65);
        if(page!=3)$fatal(1,"FAIL: strict song menu unavailable");
        tap(350,225);
        if(send || page!=3)$fatal(1,"FAIL: strict UI allowed autoplay preview");
        choose(3);
        if(mode!=0)$fatal(1,"FAIL: strict router allowed an injected autoplay command");
        choose(2);repeat(20000)@(negedge clk);
        if(mode!=2 || router.u_game.hits!=0)$fatal(1,"FAIL: strict game routing changed");
        tap(100,225);
        if(ui_mode!=2)$fatal(1,"FAIL: strict build disabled player game");
        $display("PASS: strict UI/router reject autoplay; player game enabled; no musical note without plucking");$finish;
    end
    initial begin #2000000;$fatal(1,"FAIL: competition control watchdog");end
endmodule
