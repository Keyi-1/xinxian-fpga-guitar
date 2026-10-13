// One shared restoring divider; no DSP and no variable divide on pixel paths.
module touch_coordinate_mapper #(
    parameter integer SWAP_AXES=-1, MIRROR_X=0, MIRROR_Y=0
)(input wire clk,rst_n,frame_valid,input wire [3:0] count,
  input wire [7:0] track_id,input wire [15:0] raw_x,raw_y,max_x,max_y,
  output reg valid,output reg [3:0] mapped_count,output reg [7:0] mapped_id,
  output reg [8:0] x,y);
    reg [1:0] state;
    reg [24:0] numerator;
    reg [16:0] remainder,next_remainder;
    reg [15:0] denominator,axis_y,range_y;
    reg [24:0] quotient;
    reg [4:0] bit_count;
    wire swap_axes=SWAP_AXES<0 ? max_x==272 && max_y==480 : SWAP_AXES!=0;
    wire [15:0] ax=swap_axes ? raw_y : raw_x;
    wire [15:0] ay=swap_axes ? raw_x : raw_y;
    wire [15:0] rx=swap_axes ? max_y : max_x;
    wire [15:0] ry=swap_axes ? max_x : max_y;
    always @* next_remainder={remainder[15:0],numerator[24]};
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=0;valid<=0;mapped_count<=0;mapped_id<=0;x<=0;y<=0;
            numerator<=0;remainder<=0;denominator<=1;axis_y<=0;range_y<=1;quotient<=0;bit_count<=0;
        end else begin
            valid<=0;
            if(state==0 && frame_valid)begin
                mapped_count<=count;mapped_id<=track_id;
                if(count!=1)valid<=1;
                else if(rx==0 || ry==0 || ax>=rx || ay>=ry)begin mapped_count<=15;valid<=1;end
                else begin
                    numerator<=({9'd0,ax}<<9)-({9'd0,ax}<<5);denominator<=rx;
                    axis_y<=ay;range_y<=ry;remainder<=0;quotient<=0;bit_count<=24;state<=1;
                end
            end else if(state==1 || state==2)begin
                numerator<={numerator[23:0],1'b0};
                if(next_remainder>={1'b0,denominator})begin
                    remainder<=next_remainder-{1'b0,denominator};quotient<={quotient[23:0],1'b1};
                end else begin remainder<=next_remainder;quotient<={quotient[23:0],1'b0};end
                if(bit_count==0)state<=state==1 ? 3 : 0;
                else bit_count<=bit_count-1'b1;
                if(bit_count==0 && state==2)begin
                    y<=MIRROR_Y!=0 ? 9'd271-{quotient[7:0],next_remainder>={1'b0,denominator}} :
                                                    {quotient[7:0],next_remainder>={1'b0,denominator}};
                    valid<=1;
                end
            end else if(state==3)begin
                x<=MIRROR_X!=0 ? 9'd479-quotient[8:0] : quotient[8:0];
                numerator<=({9'd0,axis_y}<<8)+({9'd0,axis_y}<<4);denominator<=range_y;
                remainder<=0;quotient<=0;bit_count<=24;state<=2;
            end
        end
    end
endmodule
