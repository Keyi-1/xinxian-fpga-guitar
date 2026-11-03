"""Emit the pipelined native RGB compositor and small radial threshold cases."""
from pathlib import Path
import math
root=Path(__file__).resolve().parent.parent
old=(root/'rtl/display/guitar_lissajous_palette.v').read_text()
glyph=old[old.index('    function [34:0] glyph;'):old.index('    function [5:0] clamp;')]
s=r'''// Five geometry/font stages; curve RAM-to-RGB path is four stages.
// Both settle before phase 5 of the existing six-clock pixel scanner.
module guitar_radial_palette(input wire clk,rst_n,frame_start,visual_update,
    input wire [8:0] x,y,input wire [11:0] mask,
    input wire [3:0] voice_active,flash,input wire [43:0] hz,
    input wire [15:0] fret,level,input wire [31:0] strikes,
    input wire [159:0] targets,output reg [17:0] rgb,
    output wire [3:0] curve_active) /* synthesis syn_romstyle="logic" */;
    wire [31:0] curve_gain;
    guitar_curve_envelope u_curve_envelope(.clk(clk),.rst_n(rst_n),.visual_update(visual_update),
        .voice_active(voice_active),.level(level),.strikes(strikes),
        .gain(curve_gain),.curve_active(curve_active));
    wire [47:0] digits;
    guitar_hz_bcd u_digits(.clk(clk),.rst_n(rst_n),.hz(hz),.digits(digits));
    reg [4:0] envelope [0:3];
    reg [4:0] heights [0:63],peaks [0:63];
    reg [31:0] old_strikes;
    reg [5:0] hue_count;
    reg [1:0] peak_divider;
    integer i;
    reg [5:0] raw_target,previous_target,next_target;
    reg [7:0] smoothed;
    reg [4:0] next_height;
    function [4:0] interpolated;
        input [5:0] bar;
        reg [5:0] sum;
        begin
            if(!bar[0] || bar==63)interpolated=targets[bar[5:1]*5+:5];
            else begin sum={1'b0,targets[bar[5:1]*5+:5]}+{1'b0,targets[(bar[5:1]+5'd1)*5+:5]}+1'b1;
                interpolated=sum[5:1];end
        end
    endfunction
    always @(posedge clk)begin
        if(!rst_n)begin
            old_strikes<=0;hue_count<=0;peak_divider<=0;
            for(i=0;i<4;i=i+1)envelope[i]<=0;
            for(i=0;i<64;i=i+1)begin heights[i]<=0;peaks[i]<=0;end
        end else if(visual_update)begin
            old_strikes<=strikes;hue_count<=hue_count+1'b1;peak_divider<=peak_divider+1'b1;
            for(i=0;i<4;i=i+1)
                if(strikes[i*8+:8]!=old_strikes[i*8+:8])envelope[i]<=31;
                else if(envelope[i]!=0)envelope[i]<=envelope[i]-1'b1;
            for(i=0;i<64;i=i+1)begin
                raw_target={1'b0,interpolated(i[5:0])};
                previous_target={1'b0,interpolated(i==0 ? 6'd0 : i[5:0]-1'b1)};
                next_target={1'b0,interpolated(i==63 ? 6'd63 : i[5:0]+1'b1)};
                smoothed=({2'd0,raw_target}<<1)+{2'd0,previous_target}+{2'd0,next_target}+8'd2;
                next_height=smoothed[6:2];
                if(next_height>heights[i])begin
                    smoothed={3'd0,heights[i]}+({3'd0,next_height}<<1)+{3'd0,next_height}+8'd3;
                    next_height=smoothed[6:2];
                end else if(next_height<heights[i])next_height=heights[i]-1'b1;
                heights[i]<=next_height;
                if(next_height>=peaks[i])peaks[i]<=next_height;
                else if(peak_divider==3 && peaks[i]!=0)peaks[i]<=peaks[i]-1'b1;
            end
        end
    end
__GLYPH__
    function [5:0] clamp;
        input [7:0] value;begin clamp=value>63 ? 6'd63 : value[5:0];end
    endfunction
    function [17:0] wheel;
        input [7:0] hue_in;input [5:0] strength;
        reg [7:0] hue;
    integer c;
        reg [5:0] rising,falling,low;
        begin
            hue=hue_in>=192 ? hue_in-8'd192 : hue_in;
            case(hue[4:3])
                0:rising=0;1:rising=strength>>2;2:rising=strength>>1;
                default:rising=(strength>>1)+(strength>>2);
            endcase
            falling=strength-rising;low=strength>>3;
            case(hue[7:5])
                0:wheel={strength,rising,low};1:wheel={falling,strength,low};
                2:wheel={low,strength,rising};3:wheel={low,falling,strength};
                4:wheel={rising,low,strength};default:wheel={strength,low,falling};
            endcase
        end
    endfunction
    function [17:0] stripe_color;
        input [1:0] card;input [5:0] strength;
        begin case(card)
            0:stripe_color={strength>>3,strength>>2,strength};
            1:stripe_color={strength>>3,strength,strength>>2};
            2:stripe_color={strength,strength>>1,strength>>4};
            default:stripe_color={strength,strength>>3,strength>>4};
        endcase end
    endfunction
    function [16:0] radius_square;
        input [4:0] height;
        begin case(height)
__RADIUS__
            default:radius_square=17'd72900;
        endcase end
    endfunction
    function [4:0] radius_depth;
        input [7:0] squared_bucket;
        begin case(squared_bucket)
__DEPTH__
            default:radius_depth=0;
        endcase end
    endfunction
    reg [8:0] x1,y1,x2,y2,x3,y3,x4,y4;
    reg [1:0] card1;
    reg [6:0] local_y1;
    reg [11:0] card_digits1;
    reg [3:0] card_fret1;
    wire [1:0] card0=y>=204 ? 2'd3 : y>=136 ? 2'd2 : y>=68 ? 2'd1 : 2'd0;
    reg [8:0] local_y0;
    always @* case(card0)
        0:local_y0=y;1:local_y0=y-9'd68;2:local_y0=y-9'd136;default:local_y0=y-9'd204;
    endcase
    wire signed [10:0] dx0=$signed({1'b0,x,1'b0})-11'sd687;
    wire signed [10:0] dy0=$signed({1'b0,y,1'b0})-11'sd271;
    reg signed [9:0] dx1,dy1;
    wire [8:0] ax1=dx1[9] ? -dx1 : dx1,ay1=dy1[9] ? -dy1 : dy1;
    wire [19:0] sx=dx1*dx1,sy=dy1*dy1;
    wire [20:0] square_sum={1'b0,sx}+{1'b0,sy};
    reg [17:0] squared2,squared3,squared4;
    reg [8:0] u2,v2,u3,v3;
    reg [1:0] quadrant2,quadrant3;
    reg swapped2,swapped3;
    reg [17:0] scaled_u3,threshold3 [0:6];
    reg [2:0] octant;
    reg [5:0] angle4;
    reg gap4;
    reg [4:0] depth4;
    reg gap;
    integer k;
    always @* begin
        octant=0;
        for(k=0;k<7;k=k+1)if(scaled_u3>=threshold3[k])octant=k+1;
        gap=u3<=1 || v3-u3<=1;
        for(k=0;k<7;k=k+1)
            if(scaled_u3>=threshold3[k]-18'd128 && scaled_u3<=threshold3[k]+18'd128)gap=1;
    end
    reg [11:0] mask1;
    reg [7:0] rr,gg,bb,r2,g2,b2,r3,g3,b3;
    reg [5:0] strength;
    reg [17:0] contribution;
    reg [7:0] hue;
    integer c;
    always @* begin
        rr=0;gg=0;bb=0;strength=0;contribution=0;hue=0;
        for(c=0;c<4;c=c+1)if(mask1[c*3+:3]!=0 && curve_active[c])begin
            strength=curve_gain[c*8+2+:6];
            case(mask1[c*3+:3])
                7:strength=strength;6:strength=strength-(strength>>3);
                4:strength=strength>>1;2:strength=strength>>2;default:strength=strength>>3;
            endcase
            case(c)0:hue=128;1:hue=64;2:hue=16;default:hue=0;endcase
            hue=hue+(hue_count[5] ? {4'd0,~hue_count[4:1]} : {4'd0,hue_count[4:1]})+
                {5'd0,x1[4:2]}+{5'd0,y1[4:2]};
            contribution=wheel(hue,strength);
            rr=rr+{2'd0,contribution[17:12]};gg=gg+{2'd0,contribution[11:6]};bb=bb+{2'd0,contribution[5:0]};
        end
    end
    wire [8:0] horizontal_fall=x1<208 ? 9'd208-x1 : 9'd0;
    wire [6:0] vertical_fall=local_y1<34 ? local_y1 : 7'd67-local_y1;
    wire [6:0] spatial={1'b0,horizontal_fall[7:2]}+{3'd0,vertical_fall[5:2]};
    wire [5:0] spatial_clamped=spatial>63 ? 6'd63 : spatial[5:0];
    reg [10:0] stripe_product2;
    reg [5:0] stripe_strength3;
    reg [6:0] font_offset,font_base;
    reg [2:0] font_cell,font_y,font_x;
    reg [7:0] letter;
    reg [17:0] font_color;
    reg [7:0] letter2;
    reg [2:0] fx2,fy2;
    reg visible2,text3,text4;
    reg [17:0] text_color2,text_color3,text_color4;
    reg [4:0] glyph_row;
    wire [34:0] bits=glyph(letter2);
    always @* case(fy2)
        0:glyph_row=bits[34:30];1:glyph_row=bits[29:25];2:glyph_row=bits[24:20];
        3:glyph_row=bits[19:15];4:glyph_row=bits[14:10];5:glyph_row=bits[9:5];
        6:glyph_row=bits[4:0];default:glyph_row=0;
    endcase
    always @* begin
        font_offset=x1<208 ? x1-9'd16 : x1-9'd309;
        font_cell=font_offset>=60 ? 5 : font_offset>=48 ? 4 : font_offset>=36 ? 3 :
            font_offset>=24 ? 2 : font_offset>=12 ? 1 : 0;
        case(font_cell)0:font_base=0;1:font_base=12;2:font_base=24;3:font_base=36;4:font_base=48;default:font_base=60;endcase
        font_x=(font_offset-font_base)>>1;font_y=0;letter=0;
        font_color=voice_active[card1] ? {6'd52,6'd56,6'd63} : {6'd18,6'd24,6'd34};
        if(x1>=16 && x1<76 && local_y1>=12 && local_y1<26)begin
            font_y=(local_y1-7'd12)>>1;
            case(font_cell)0:letter=8'd49+{6'd0,card1};2:letter="F";
                3:letter=8'd48+{4'd0,card_fret1};default:letter=0;endcase
        end else if(x1>=16 && x1<76 && local_y1>=36 && local_y1<50)begin
            font_y=(local_y1-7'd36)>>1;
            case(font_cell)
                0:letter=8'd48+{4'd0,card_digits1[11:8]};
                1:letter=8'd48+{4'd0,card_digits1[7:4]};
                2:letter=8'd48+{4'd0,card_digits1[3:0]};3:letter="H";4:letter="Z";default:letter=0;
            endcase
        end else if(x1>=309 && x1<381 && y1>=40 && y1<54)begin
            font_y=(y1-9'd40)>>1;font_color={6'd33,6'd44,6'd55};
            case(font_cell)0:letter="P";1:letter="O";2:letter="L";3:letter="Y";4:letter="X";default:letter="Y";endcase
        end else if(x1>=309 && x1<381 && y1>=219 && y1<233)begin
            font_y=(y1-9'd219)>>1;font_color={6'd20,6'd32,6'd43};
            case(font_cell)0:letter="R";1:letter="E";2:letter="F";3:letter="2";4:letter="2";default:letter="0";endcase
        end
    end
    reg [7:0] red,green,blue;
    reg [17:0] tint;
    reg [4:0] h,p;
    reg [5:0] spectrum_strength;
    reg [7:0] spectrum_hue;
    always @* begin
        red=1;green=2;blue=5;tint=0;h=heights[angle4];p=peaks[angle4];
        spectrum_strength=depth4>=24 ? 6'd63 : 6'd15+{depth4,1'b0};
        spectrum_hue={2'd0,angle4}+({2'd0,angle4}<<1);
        spectrum_hue=spectrum_hue>=64 ? spectrum_hue-8'd64 : spectrum_hue+8'd128;
        if(x4<208)begin
            tint=stripe_color(y4>=204 ? 2'd3 : y4>=136 ? 2'd2 : y4>=68 ? 2'd1 : 2'd0,stripe_strength3);
            red=red+{2'd0,tint[17:12]};green=green+{2'd0,tint[11:6]};blue=blue+{2'd0,tint[5:0]};
            if(x4<4 || y4==0 || y4==68 || y4==136 || y4==204)begin red=2;green=3;blue=6;end
        end else begin
            if(squared4<18'd44521)begin
                if(x4[4:0]==0 || y4[4:0]==0)begin green=4;blue=8;end
                red=red+r3;green=green+g3;blue=blue+b3;
            end
            if(squared4>=18'd44521 && squared4<=18'd45369)begin red=5;green=9;blue=15;end
            if(!gap4 && h!=0 && squared4>=18'd45796 && squared4<={1'b0,radius_square(h)})begin
                tint=wheel(spectrum_hue,spectrum_strength);
                red={2'd0,tint[17:12]};green={2'd0,tint[11:6]};blue={2'd0,tint[5:0]};
            end
            if(!gap4 && p!=0 && squared4>{1'b0,radius_square(p)} &&
               squared4<={1'b0,radius_square(p+1'b1)})begin red=38;green=48;blue=63;end
        end
        if(x4==207 || x4==208)begin red=4;green=7;blue=12;end
        if(text4)begin red={2'd0,text_color4[17:12]};green={2'd0,text_color4[11:6]};blue={2'd0,text_color4[5:0]};end
    end
    always @(posedge clk)begin
        x1<=x;y1<=y;mask1<=mask;card1<=card0;local_y1<=local_y0[6:0];
        case(card0)
            0:begin card_digits1<=digits[11:0];card_fret1<=fret[3:0];end
            1:begin card_digits1<=digits[23:12];card_fret1<=fret[7:4];end
            2:begin card_digits1<=digits[35:24];card_fret1<=fret[11:8];end
            default:begin card_digits1<=digits[47:36];card_fret1<=fret[15:12];end
        endcase
        dx1<=x>=208 ? dx0[9:0] : 10'd0;dy1<=y<272 ? dy0[9:0] : 10'd0;
        x2<=x1;y2<=y1;r2<=rr;g2<=gg;b2<=bb;squared2<=square_sum[17:0];
        u2<=ax1<ay1 ? ax1 : ay1;v2<=ax1>ay1 ? ax1 : ay1;
        quadrant2<=dy1[9] ? (dx1[9] ? 2'd3 : 2'd0) : (dx1[9] ? 2'd2 : 2'd1);
        swapped2<=dx1[9]==dy1[9] ? ay1>ax1 : ax1>ay1;
        stripe_product2<=envelope[card1]*spatial_clamped;
        letter2<=letter;fx2<=font_x;fy2<=font_y;visible2<=letter!=0 && font_x<5;text_color2<=font_color;
        x3<=x2;y3<=y2;r3<=r2;g3<=g2;b3<=b2;squared3<=squared2;
        u3<=u2;v3<=v2;scaled_u3<={1'b0,u2,8'd0};quadrant3<=quadrant2;swapped3<=swapped2;
        threshold3[0]<=({9'd0,v2}<<4)+({9'd0,v2}<<3)+{9'd0,v2};
        threshold3[1]<=({9'd0,v2}<<5)+({9'd0,v2}<<4)+({9'd0,v2}<<1)+{9'd0,v2};
        threshold3[2]<=({9'd0,v2}<<6)+({9'd0,v2}<<3)+({9'd0,v2}<<2)+({9'd0,v2}<<1);
        threshold3[3]<=({9'd0,v2}<<6)+({9'd0,v2}<<5)+({9'd0,v2}<<3)+({9'd0,v2}<<1);
        threshold3[4]<=({9'd0,v2}<<7)+({9'd0,v2}<<3)+{9'd0,v2};
        threshold3[5]<=({9'd0,v2}<<7)+({9'd0,v2}<<5)+({9'd0,v2}<<3)+({9'd0,v2}<<1)+{9'd0,v2};
        threshold3[6]<=({9'd0,v2}<<7)+({9'd0,v2}<<6)+({9'd0,v2}<<4)+({9'd0,v2}<<1);
        stripe_strength3<=stripe_product2[10:5];
        text3<=visible2 && glyph_row[3'd4-fx2];text_color3<=text_color2;
        x4<=x3;y4<=y3;squared4<=squared3;
        angle4<={quadrant3,4'd0}+{2'd0,(swapped3 ? 4'd15-{1'b0,octant} : {1'b0,octant})};
        gap4<=gap;depth4<=radius_depth(squared3[17:10]);
        text4<=text3;text_color4<=text_color3;
        rgb<={clamp(red),clamp(green),clamp(blue)};
    end
endmodule
'''
radius='\n'.join(f"            5'd{i}:radius_square=17'd{4*(107+i)**2};" for i in range(29))
depth='\n'.join(f"            8'd{i}:radius_depth=5'd{max(0,min(27,round(math.sqrt((i+.5)*1024)/2-107)))};" for i in range(43,73))
s=s.replace('__GLYPH__',glyph).replace('__RADIUS__',radius).replace('__DEPTH__',depth)
(root/'rtl/display/guitar_radial_palette.v').write_text(s,encoding='utf-8')
print('Generated five-stage radial/stripe compositor')
