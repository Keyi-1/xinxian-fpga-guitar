module touch_gesture(input wire clk,rst_n,tick_ms,flush,frame_valid,
    input wire [3:0] count,input wire [7:0] track_id,input wire [8:0] x,y,
    output reg click,double_click,output reg [8:0] click_x,click_y);
    reg down,cancelled,previous_tap;
    reg [8:0] origin_x,origin_y,last_x,last_y;
    reg [7:0] origin_id;
    reg [9:0] held_ms,gap_ms;
    wire [8:0] dx=x>origin_x ? x-origin_x : origin_x-x;
    wire [8:0] dy=y>origin_y ? y-origin_y : origin_y-y;
    wire [8:0] tap_dx=origin_x>last_x ? origin_x-last_x : last_x-origin_x;
    wire [8:0] tap_dy=origin_y>last_y ? origin_y-last_y : last_y-origin_y;
    always @(posedge clk)begin
        if(!rst_n || flush)begin
            down<=0;cancelled<=0;previous_tap<=0;held_ms<=0;gap_ms<=1023;
            click<=0;double_click<=0;click_x<=0;click_y<=0;origin_x<=0;origin_y<=0;
            last_x<=0;last_y<=0;origin_id<=0;
        end else begin
            click<=0;double_click<=0;
            if(tick_ms)begin
                if(down && held_ms!=1023)held_ms<=held_ms+1'b1;
                if(gap_ms!=1023)gap_ms<=gap_ms+1'b1;
                if(gap_ms>=350)previous_tap<=0;
            end
            if(frame_valid)begin
                if(count==1 && !down)begin
                    down<=1;origin_x<=x;origin_y<=y;origin_id<=track_id;held_ms<=0;
                end else if(count==1 && down)begin
                    if(track_id!=origin_id || dx>32 || dy>32)cancelled<=1;
                end else if(count>1)begin cancelled<=1;previous_tap<=0;end
                else if(count==0)begin
                    if(down && !cancelled && held_ms<=180)begin
                        click<=1;click_x<=origin_x;click_y<=origin_y;
                        if(previous_tap && gap_ms>=80 && gap_ms<=350 && tap_dx<=32 && tap_dy<=32)begin
                            double_click<=1;previous_tap<=0;
                        end else begin previous_tap<=1;gap_ms<=0;last_x<=origin_x;last_y<=origin_y;end
                    end
                    down<=0;cancelled<=0;
                end
            end
        end
    end
endmodule
