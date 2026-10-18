// Two new buttons occupy only the previously unused bottom of the home page.
// Calibration is deliberate; every power-on starts in MANUAL.
module posture_touch_controls(input wire clk,rst_n,click,double_click,touch_ready,
    input wire [2:0] page,input wire transition,import_locked,
    input wire [8:0] click_x,click_y,
    input wire ready,calibrated,calibrating,healthy,
    output reg calibrate,auto_enable);
    always @(posedge clk)begin
        if(!rst_n)begin calibrate<=0;auto_enable<=0;end
        else begin
            calibrate<=0;
            if(click && !double_click && touch_ready && page==0 && !transition && !import_locked && click_y>=240)begin
                if(click_x>=16 && click_x<144)begin calibrate<=1;auto_enable<=0;end
                else if(click_x>=160 && click_x<288)begin
                    if(auto_enable)auto_enable<=0;
                    else if(ready && calibrated && !calibrating && healthy)auto_enable<=1;
                end
            end
        end
    end
endmodule
