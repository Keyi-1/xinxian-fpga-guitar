// Pages: home, performance, songs, ready, countdown, game, result.
// Empty song slots have no action. Touch failure falls back to performance.
module touch_game_ui #(
    parameter integer FALLBACK_MS=2000,
    parameter integer ALLOW_AUTOPLAY_PREVIEW=1
)(input wire clk,rst_n,tick_ms,touch_ready,click,double_click,
  input wire [8:0] click_x,click_y,input wire [255:0] game_snapshot,
  input wire command_busy,command_done,
  output reg command_send,output reg [1:0] command_mode,
  output reg [2:0] page,output reg flush_gesture,output wire transition);
    reg waiting;
    reg [2:0] pending_page;
    reg [15:0] missing_ms;
    assign transition=waiting || command_busy;
    task request_mode;
        input [1:0] new_mode;input [2:0] new_page;
        begin command_mode<=new_mode;pending_page<=new_page;waiting<=1;command_send<=1;flush_gesture<=1;end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            command_send<=0;command_mode<=0;page<=0;flush_gesture<=0;waiting<=0;pending_page<=0;missing_ms<=0;
        end else begin
            command_send<=0;flush_gesture<=0;
            if(touch_ready)missing_ms<=0;
            else if(tick_ms && missing_ms<FALLBACK_MS)missing_ms<=missing_ms+1'b1;
            if(command_done && waiting)begin page<=pending_page;waiting<=0;flush_gesture<=1;end
            else if(!transition)begin
                if(!touch_ready && missing_ms>=FALLBACK_MS && page!=1)request_mode(1,1);
                else if((page==1 || page==4 || page==5) && double_click)request_mode(0,0);
                else if((page==4 || page==5) && game_snapshot[235] && game_snapshot[233:232]>=2)request_mode(0,6);
                else if(page==4 && game_snapshot[233:232]>=2 && !game_snapshot[234])page<=5;
                else if(click)case(page)
                    0:if(click_y>=94 && click_y<=227)begin
                        if(click_x>=24 && click_x<=227)request_mode(1,1);
                        else if(click_x>=252 && click_x<=455)begin page<=2;flush_gesture<=1;end
                    end
                    2:if(click_y>=48 && click_y<92 && click_x>=24 && click_x<=455)begin page<=3;flush_gesture<=1;end
                      else if(click_y<40 && click_x<80)begin page<=0;flush_gesture<=1;end
                    3:if(click_y>=198 && click_y<=252)begin
                        if(click_x>=40 && click_x<230)request_mode(2,4);
                        else if(ALLOW_AUTOPLAY_PREVIEW && click_x>=250 && click_x<=440)request_mode(3,4);
                    end else if(click_y<40 && click_x<80)begin page<=2;flush_gesture<=1;end
                    6:if(click_y>=208 && click_y<=260)begin
                        if(click_x>=24 && click_x<160)begin page<=3;flush_gesture<=1;end
                        else if(click_x>=172 && click_x<308)begin page<=2;flush_gesture<=1;end
                        else if(click_x>=320 && click_x<=456)begin page<=0;flush_gesture<=1;end
                    end
                endcase
            end
        end
    end
endmodule
