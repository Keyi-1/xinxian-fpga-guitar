// Procedural RGB666 color: rainbow halo, white moving highlight, navy grid,
// sparse stars, a LIVE/HOLD indicator and the current frequency-ratio badge.
module lcd_neon_palette (
    input wire clk,
    input wire [8:0] x,y,
    input wire [3:0] intensity,
    input wire [15:0] animation_phase,
    input wire [1:0] mode,
    input wire paused,
    output reg [17:0] rgb
);
    wire [7:0] hue=x[8:1]+y[7:0]+animation_phase[8:1];
    wire [7:0] hue_g=hue+8'd85, hue_b=hue+8'd170;
    function [5:0] triangle;
        input [7:0] value;
        begin triangle=value[7] ? ~value[6:1] : value[6:1]; end
    endfunction
    function [5:0] saturate;
        input [7:0] value;
        begin saturate=value>63 ? 6'd63 : value[5:0]; end
    endfunction
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
                default: glyph=0;
            endcase
        end
    endfunction
    reg [7:0] letter;
    reg [34:0] bits;
    integer cell_index, font_x, font_y;
    reg text_on;
    reg [7:0] red,green,blue;
    reg [9:0] r_energy,g_energy,b_energy;
    reg [5:0] color_r1,color_g1,color_b1,color_r2,color_g2,color_b2;
    reg [8:0] x1,y1,px,py;
    reg [3:0] light1,light2;
    reg [1:0] mode1,mode2;
    reg pause1,pause2;
    reg [17:0] rgb_next;
    // Six board cycles per pixel leave enough time for RAM plus three color
    // stages. Metadata travels with intensity; outputs are latched at phase 5.
    always @(posedge clk) begin
        color_r1<=triangle(hue); color_g1<=triangle(hue_g); color_b1<=triangle(hue_b);
        x1<=x; y1<=y; light1<=intensity; mode1<=mode; pause1<=paused;
        r_energy<=color_r1*light1; g_energy<=color_g1*light1; b_energy<=color_b1*light1;
        px<=x1; py<=y1; light2<=light1; mode2<=mode1; pause2<=pause1;
        color_r2<=color_r1; color_g2<=color_g1; color_b2<=color_b1;
        rgb<=rgb_next;
    end
    wire grid=px[4:0]==0 || py[4:0]==0;
    wire star=(px[4:0]==(px[8:5]^py[7:4])) &&
              (py[4:0]==(px[7:3]^5'd19)) && ((px[8:5]^py[8:5])==4'd7);
    always @* begin
        red=8'd2+{2'd0,r_energy[9:4]};
        green=8'd3+{2'd0,g_energy[9:4]};
        blue=8'd6+{2'd0,b_energy[9:4]}+{5'd0,py[8:6]};
        if(grid) begin red=red+1; green=green+2; blue=blue+3; end
        if(star) begin red=red+10; green=green+12; blue=blue+15; end
        if(light2>=14) begin red=red+15; green=green+15; blue=blue+15; end
        if(py==255 && px>=120 && px<464) begin
            red={2'd0,color_r2}; green={2'd0,color_g2}; blue={2'd0,color_b2};
        end
        if(py>=254 && py<258 && px>=16 && px<104) begin
            if(((px-16)/22)==mode2 && ((px-16)%22)<16) begin
                red=45; green=55; blue=63;
            end else if(((px-16)%22)<16) begin red=6; green=10; blue=17; end
        end
        cell_index=0; font_x=0; font_y=0; letter=0; text_on=0; bits=0;
        if(py>=10 && py<24 && px>=16 && px<124) begin
            cell_index=(px-16)/12; font_x=((px-16)%12)/2; font_y=(py-10)/2;
            case(cell_index)
                0:letter="L"; 1:letter="I"; 2:letter="S"; 3:letter="S";
                4:letter="A"; 5:letter="J"; 6:letter="O"; 7:letter="U"; 8:letter="S";
                default:letter=0;
            endcase
        end else if(py>=10 && py<24 && px>=336 && px<384) begin
            cell_index=(px-336)/12; font_x=((px-336)%12)/2; font_y=(py-10)/2;
            if(pause2) case(cell_index)
                0:letter="H"; 1:letter="O"; 2:letter="L"; 3:letter="D"; default:letter=0;
            endcase
            else case(cell_index)
                0:letter="L"; 1:letter="I"; 2:letter="V"; 3:letter="E"; default:letter=0;
            endcase
        end else if(py>=10 && py<24 && px>=416 && px<452) begin
            cell_index=(px-416)/12; font_x=((px-416)%12)/2; font_y=(py-10)/2;
            if(cell_index==1) letter=":";
            else case(mode2)
                0:letter=cell_index==0 ? "3" : "2";
                1:letter=cell_index==0 ? "5" : "4";
                2:letter=cell_index==0 ? "7" : "5";
                default:letter=cell_index==0 ? "9" : "8";
            endcase
        end
        bits=glyph(letter);
        if(letter!=0 && font_x<5) text_on=bits[34-font_y*5-font_x];
        if(text_on) begin red=45; green=55; blue=63; end
        rgb_next={saturate(red),saturate(green),saturate(blue)};
    end
endmodule
