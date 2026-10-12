// Four board-clock stages: mask, colors/font coordinates, glyph, saturation.
// Fixed character cells use narrow comparisons; no divide/modulo hardware.
module guitar_lissajous_palette(input wire clk,rst_n,frame_start,input wire [8:0] x,y,
    input wire [11:0] mask,input wire [3:0] voice_active,flash,input wire [43:0] hz,
    input wire [15:0] fret,level,output reg [17:0] rgb);
    wire [47:0] digits;
    reg [7:0] hue_count;
    always @(posedge clk)
        if(!rst_n)hue_count<=0;
        else if(frame_start)hue_count<=hue_count==191 ? 8'd0 : hue_count+1'b1;
    guitar_hz_bcd u_digits(.clk(clk),.rst_n(rst_n),.hz(hz),.digits(digits));
    function [34:0] glyph;
        input [7:0] letter;
        begin
            // Seven rows, five bits per row, top row in bits 34..30.
            case(letter)
                "L": glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "I": glyph=35'b11111_00100_00100_00100_00100_00100_11111;
                "S": glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "A": glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "J": glyph=35'b00111_00010_00010_00010_10010_10010_01100;
                "O": glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "U": glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "V": glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "E": glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "H": glyph=35'b10001_10001_10001_11111_10001_10001_10001;
                "D": glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "2": glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3": glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4": glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5": glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "7": glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8": glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9": glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                ":": glyph=35'b00000_00100_00100_00000_00100_00100_00000;
                "0": glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1": glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "6": glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "F": glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "R": glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "P": glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "Y": glyph=35'b10001_10001_01010_00100_00100_00100_00100;
                "X": glyph=35'b10001_10001_01010_00100_01010_10001_10001;
                "Z": glyph=35'b11111_00001_00010_00100_01000_10000_11111;
                default: glyph=0;
            endcase
        end
    endfunction
    function [5:0] clamp;
        input [7:0] value;
        begin clamp=value>63 ? 6'd63 : value[5:0]; end
    endfunction
    function [17:0] color;
        input [1:0] index;input [5:0] strength;input [7:0] spatial_hue;
        reg [8:0] hue;
        reg [5:0] rising,falling,low;
        begin
            case(index)
                0:hue={1'b0,hue_count}+spatial_hue;
                1:hue={1'b0,hue_count}+9'd96+spatial_hue;
                2:hue={1'b0,hue_count}+9'd24+spatial_hue;
                default:hue={1'b0,hue_count}+9'd144+spatial_hue;
            endcase
            if(hue>=192)hue=hue-192;
            // Quarter-strength interpolation uses shifts, leaving DSPs free.
            case(hue[4:3])
                0:rising=0;1:rising=strength>>2;2:rising=strength>>1;
                default:rising=(strength>>1)+(strength>>2);
            endcase
            falling=strength-rising;low=strength>>3;
            case(hue[7:5])
                0:color={strength,rising,low};
                1:color={falling,strength,low};
                2:color={low,strength,rising};
                3:color={low,falling,strength};
                4:color={rising,low,strength};
                default:color={strength,low,falling};
            endcase
        end
    endfunction
    reg [8:0] x1,y1,x2,y2,x3,y3;
    reg [11:0] mask1;
    reg [7:0] r2,g2,b2,r3,g3,b3;
    reg [7:0] font_letter2;
    reg [2:0] font_x2,font_y2;
    reg font_visible2,text3;
    reg [17:0] text_color2,text_color3;
    reg [7:0] rr,gg,bb;
    reg [17:0] contribution;
    reg [5:0] strength;
    integer i;
    always @* begin
        rr=0;gg=0;bb=0;contribution=0;strength=0;
        for(i=0;i<4;i=i+1) if(mask1[i*3+:3]!=0 && voice_active[i]) begin
            strength=6'd22+{1'b0,level[i*4+:4],1'b0}+(flash[i] ? 6'd8 : 6'd0);
            case(mask1[i*3+:3])
                7:strength=strength;
                6:strength=strength-(strength>>3);
                4:strength=strength>>1;
                2:strength=strength>>2;
                default:strength=strength>>3;
            endcase
            contribution=color(i[1:0],strength,{5'd0,x1[4:2]}+{5'd0,y1[4:2]});
            rr=rr+{2'd0,contribution[17:12]};
            gg=gg+{2'd0,contribution[11:6]};
            bb=bb+{2'd0,contribution[5:0]};
        end
        // Coverage comes from the native-pixel scan converter; no magnification.
    end
    reg [1:0] card,card0;
    reg [8:0] local_x,local_x0;
    reg [6:0] header_offset,header_base;
    reg [4:0] card_offset,card_base;
    reg [2:0] header_cell,card_cell,font_y;
    reg [6:0] font_x;
    reg [7:0] letter;
    reg [17:0] text_color;
    always @* begin
        card0=x>=360 ? 2'd3 : x>=240 ? 2'd2 : x>=120 ? 2'd1 : 2'd0;
        case(card0)
            0:local_x0=x;1:local_x0=x-9'd120;2:local_x0=x-9'd240;default:local_x0=x-9'd360;
        endcase
    end
    always @* begin
        // Card origin is registered with x1, before the font selection stage.
        header_offset=x1>=368 ? x1-9'd368 : x1-9'd16;
        header_cell=header_offset>=72 ? 3'd6 : header_offset>=60 ? 3'd5 :
            header_offset>=48 ? 3'd4 : header_offset>=36 ? 3'd3 :
            header_offset>=24 ? 3'd2 : header_offset>=12 ? 3'd1 : 3'd0;
        case(header_cell)
            0:header_base=0;1:header_base=12;2:header_base=24;
            3:header_base=36;4:header_base=48;5:header_base=60;default:header_base=72;
        endcase
        card_offset=local_x-9'd8;
        card_cell=card_offset>=24 ? 3'd4 : card_offset>=18 ? 3'd3 :
            card_offset>=12 ? 3'd2 : card_offset>=6 ? 3'd1 : 3'd0;
        case(card_cell)
            0:card_base=0;1:card_base=6;2:card_base=12;3:card_base=18;default:card_base=24;
        endcase
        font_x=0;font_y=0;letter=0;
        text_color=color(card,voice_active[card] ? 6'd55 : 6'd20,8'd0);
        if(y1>=10 && y1<24 && x1>=16 && x1<100) begin
            font_x=(header_offset-header_base)>>1;font_y=(y1-9'd10)>>1;
            if(x1<28)letter="P";else if(x1<40)letter="O";
            else if(x1<52)letter="L";else if(x1<64)letter="Y";
            else if(x1<76)letter=0;else if(x1<88)letter="X";else letter="Y";
            text_color={6'd42,6'd52,6'd63};
        end else if(y1>=10 && y1<24 && x1>=368 && x1<452) begin
            font_x=(header_offset-header_base)>>1;font_y=(y1-9'd10)>>1;
            if(x1<380)letter="R";else if(x1<392)letter="E";
            else if(x1<404)letter="F";else if(x1<416)letter=0;
            else if(x1<440)letter="2";else letter="0";
            text_color={6'd25,6'd35,6'd48};
        end else if(y1>=248 && y1<255 && local_x>=8 && local_x<38) begin
            font_x={2'd0,card_offset-card_base};font_y=y1-9'd248;
            case(card_cell)
                0:letter=8'd49+{6'd0,card};
                2:letter="F";
                3:letter=8'd48+{4'd0,fret[card*4+:4]};
                default:letter=0;
            endcase
        end else if(y1>=261 && y1<268 && local_x>=8 && local_x<38) begin
            font_x={2'd0,card_offset-card_base};font_y=y1-9'd261;
            case(card_cell)
                0:letter=8'd48+{4'd0,digits[card*12+8+:4]};
                1:letter=8'd48+{4'd0,digits[card*12+4+:4]};
                2:letter=8'd48+{4'd0,digits[card*12+:4]};
                3:letter="H";4:letter="Z";default:letter=0;
            endcase
        end
    end
    wire [34:0] font_bits=glyph(font_letter2);
    reg [4:0] font_row;
    always @* case(font_y2)
        0:font_row=font_bits[34:30];1:font_row=font_bits[29:25];
        2:font_row=font_bits[24:20];3:font_row=font_bits[19:15];
        4:font_row=font_bits[14:10];5:font_row=font_bits[9:5];
        6:font_row=font_bits[4:0];default:font_row=0;
    endcase
    reg [7:0] red,green,blue;
    reg [1:0] card2;
    reg [8:0] lx2;
    reg [17:0] tint;
    always @* begin
        red=8'd2+r3;green=8'd3+g3;blue=8'd7+b3;
        if(x3[5:0]==0 || y3[5:0]==0) begin green=green+2;blue=blue+3;end
        card2=x3>=360 ? 2'd3 : x3>=240 ? 2'd2 : x3>=120 ? 2'd1 : 2'd0;
        case(card2)
            0:lx2=x3;1:lx2=x3-9'd120;2:lx2=x3-9'd240;default:lx2=x3-9'd360;
        endcase
        tint=color(card2,voice_active[card2] ? 6'd45 : 6'd12,8'd0);
        if(y3>=243) begin
            red=2;green=3;blue=6;
            if(flash[card2]) begin red=red+3;green=green+3;blue=blue+4;end
            if(y3==243 && lx2>=6 && lx2<114) begin red={2'd0,tint[17:12]};green={2'd0,tint[11:6]};blue={2'd0,tint[5:0]};end
            if(y3>=261 && y3<265 && lx2>=58 && lx2<110) begin
                if(lx2-58<({5'd0,level[card2*4+:4]}<<1)+{5'd0,level[card2*4+:4]}) begin
                    red={2'd0,tint[17:12]};green={2'd0,tint[11:6]};blue={2'd0,tint[5:0]};
                end else begin red=4;green=6;blue=10;end
            end
        end
        if(text3) begin red={2'd0,text_color3[17:12]};green={2'd0,text_color3[11:6]};blue={2'd0,text_color3[5:0]};end
    end
    always @(posedge clk) begin
        x1<=x;y1<=y;mask1<=mask;card<=card0;local_x<=local_x0;
        x2<=x1;y2<=y1;r2<=rr;g2<=gg;b2<=bb;
        font_letter2<=letter;font_x2<=font_x[2:0];font_y2<=font_y[2:0];
        font_visible2<=letter!=0 && font_x<5;text_color2<=text_color;
        x3<=x2;y3<=y2;r3<=r2;g3<=g2;b3<=b2;
        text3<=font_visible2 && font_row[3'd4-font_x2];text_color3<=text_color2;
        rgb<={clamp(red),clamp(green),clamp(blue)};
    end
endmodule
