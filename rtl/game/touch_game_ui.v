// Pages: home, performance, songs, ready, countdown, game, result.
// Empty song slots have no action. Touch failure falls back to performance.
module touch_game_ui #(
    parameter integer FALLBACK_MS=2000,
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1,USE_P2=0,WRITABLE=0
)(input wire clk,rst_n,tick_ms,touch_ready,click,double_click,
  input wire [8:0] click_x,click_y,input wire [255:0] game_snapshot,
  input wire command_busy,command_done,import_busy,input wire [4:0] overlay_valid,
  output reg command_send,output reg [1:0] command_mode,
  output reg [2:0] selected_slot,
  input wire display_fault,output reg [2:0] page,output reg flush_gesture,output wire transition);
    wire [1:0] active_mode=USE_P2 ? game_snapshot[229:228] : game_snapshot[233:232];
    wire [2:0] clicked_slot=click_y<92 ? 0 : click_y<136 ? 1 : click_y<180 ? 2 : click_y<224 ? 3 : 4;
    wire row_playable=WRITABLE ? ((5'b00111>>clicked_slot)&1'b1) || overlay_valid[clicked_slot] : clicked_slot<(USE_P2 ? 4 : 1);
    wire finished=USE_P2 ? game_snapshot[231] : game_snapshot[235];
    wire countdown=USE_P2 ? game_snapshot[230] : game_snapshot[234];
    // Layout faults clear with the new blank's generation. The countdown
    // gives that display pass time to retire an old sticky layout fault.
    wire fault=USE_P2 && (game_snapshot[233] || (display_fault && !countdown));
    reg [5:0] start_generation;
    reg song_fresh;
    wire fresh_snapshot=!USE_P2 || song_fresh ||
        (game_snapshot[255:250]!=start_generation && active_mode>=2);
    reg waiting;
    reg [2:0] pending_page;
    reg [15:0] missing_ms;
    assign transition=waiting || command_busy;
    task request_mode;
        input [1:0] new_mode;input [2:0] new_page;
        begin
            if(USE_P2 && new_mode>=2)begin start_generation<=game_snapshot[255:250];song_fresh<=0;end
            command_mode<=new_mode;pending_page<=new_page;waiting<=1;command_send<=1;flush_gesture<=1;end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            command_send<=0;command_mode<=0;selected_slot<=0;page<=0;flush_gesture<=0;waiting<=0;pending_page<=0;missing_ms<=0;start_generation<=0;song_fresh<=0;
        end else begin
            command_send<=0;flush_gesture<=0;
            if(USE_P2 && game_snapshot[255:250]!=start_generation && active_mode>=2)song_fresh<=1;
            if(touch_ready)missing_ms<=0;
            else if(tick_ms && missing_ms<FALLBACK_MS)missing_ms<=missing_ms+1'b1;
            if(command_done && waiting)begin page<=pending_page;waiting<=0;flush_gesture<=1;end
            else if(!transition && !(WRITABLE && import_busy))begin
                if(!touch_ready && missing_ms>=FALLBACK_MS && page!=1)request_mode(1,1);
                else if((page==1 || page==4 || page==5) && double_click)request_mode(0,0);
                else if((page==4 || page==5) && fresh_snapshot && (finished && active_mode>=2 || fault))request_mode(0,6);
                else if(page==4 && fresh_snapshot && active_mode>=2 && !countdown)page<=5;
                else if(click)case(page)
                    0:if(click_y>=94 && click_y<=227)begin
                        if(click_x>=24 && click_x<=227)request_mode(1,1);
                        else if(click_x>=252 && click_x<=455)begin page<=2;flush_gesture<=1;end
                    end
                    2:if(click_y>=48 && click_y<(WRITABLE ? 268 : USE_P2 ? 224 : 92) && row_playable && click_x>=24 && click_x<=455)begin page<=3;flush_gesture<=1;
                          selected_slot<=clicked_slot;end
                      else if(click_y<40 && click_x<80)begin page<=0;flush_gesture<=1;end
                    3:if(click_y>=198 && click_y<=252)begin
                        if(click_x>=40 && click_x<230)request_mode(2,4);
                        else if(ALLOW_AUTOPLAY_PREVIEW && click_x>=250 && click_x<=440)request_mode(3,4);
                    end else if(click_y<40 && click_x<80)begin page<=2;flush_gesture<=1;end
                    6:if(click_y>=208 && click_y<=260)begin
                        if(click_x>=24 && click_x<160)begin page<=3;flush_gesture<=1;
                          if(page==2)selected_slot<=click_y<92 ? 0 : click_y<136 ? 1 : click_y<180 ? 2 : 3;end
                        else if(click_x>=172 && click_x<308)begin page<=2;flush_gesture<=1;end
                        else if(click_x>=320 && click_x<=456)begin page<=0;flush_gesture<=1;end
                    end
                endcase
            end
        end
    end
endmodule
