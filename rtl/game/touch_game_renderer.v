// Four pixel stages fit the existing six-clock DCLK cadence. Eight interval
// tests are parallel within the selected lane; no framebuffer or pixel divide.
module touch_game_renderer #(parameter integer ALLOW_AUTOPLAY_PREVIEW=1)
    (input wire clk,rst_n,frame_start,input wire [2:0] page,
    input wire touch_ready,transition,input wire [8:0] x,y,
    input wire [383:0] centres,input wire [287:0] tails,input wire [31:0] valid_blocks,
    input wire [255:0] game_snapshot,output reg [17:0] rgb,output reg [2:0] display_page);
    `include "../config/game_ui_messages.vh"
    reg [7:0] animation;
    reg [19:0] score_shift,score_previous;
    reg [19:0] bcd_work,score_bcd;
    reg [4:0] bcd_bits;
    reg bcd_busy;
    // A single 8-bit double-dabble converter services the four small counters.
    // Counter formatting needs neither division nor reciprocal multiplication.
    reg [1:0] number_select;
    reg [3:0] number_step;
    reg [7:0] number_shift;
    reg [11:0] number_work,number_adjusted;
    reg [47:0] number_bcd;
    reg [19:0] bcd_adjusted;
    integer d;
    always @*begin
        bcd_adjusted=bcd_work;
        for(d=0;d<5;d=d+1)if(bcd_work[d*4+:4]>=5)bcd_adjusted[d*4+:4]=bcd_work[d*4+:4]+3;
        number_adjusted=number_work;
        for(d=0;d<3;d=d+1)if(number_work[d*4+:4]>=5)number_adjusted[d*4+:4]=number_work[d*4+:4]+3;
    end
    always @(posedge clk)begin
        if(!rst_n)begin animation<=0;display_page<=0;score_previous<=0;score_shift<=0;
            bcd_work<=0;score_bcd<=0;bcd_bits<=0;bcd_busy<=0;
            number_select<=0;number_step<=0;number_shift<=0;number_work<=0;number_bcd<=0;end
        else begin
            if(frame_start)begin animation<=animation+1'b1;display_page<=page;end
            if(!bcd_busy && score_previous!=game_snapshot[179:160])begin
                score_previous<=game_snapshot[179:160];score_shift<=game_snapshot[179:160];
                bcd_work<=0;bcd_bits<=0;bcd_busy<=1;
            end else if(bcd_busy)begin
                bcd_work<={bcd_adjusted[18:0],score_shift[19]};score_shift<={score_shift[18:0],1'b0};
                if(bcd_bits==19)begin score_bcd<={bcd_adjusted[18:0],score_shift[19]};bcd_busy<=0;end
                else bcd_bits<=bcd_bits+1'b1;
            end
            if(number_step==0)begin
                number_shift<=game_snapshot[180+number_select*8+:8];number_work<=0;number_step<=1;
            end else begin
                number_shift<={number_shift[6:0],1'b0};number_work<={number_adjusted[10:0],number_shift[7]};
                if(number_step==8)begin
                    number_bcd[number_select*12+:12]<={number_adjusted[10:0],number_shift[7]};
                    number_select<=number_select+1'b1;number_step<=0;
                end else number_step<=number_step+1'b1;
            end
        end
    end
    reg [17:0] background;
    reg [6:0] glyph;
    reg [9:0] message_address;
    reg numeric_glyph;
    reg [3:0] font_row,font_col;
    reg text_enable;
    reg [1:0] lane;
    reg [8:0] lane_origin;
    reg [2:0] lane_judgement;
    reg [6:0] local_y;
    reg [7:0] head_hits,tail_hits;
    reg [11:0] centre,tail_end;
    reg [4:0] slot;
    integer k;
    wire [4:0] breath=animation[5] ? ~animation[4:0] : animation[4:0];
    task label;
        input [4:0] message_id;input integer origin_x,origin_y,characters,scale,ascii;
        reg [8:0] dx,dy;reg [4:0] character_index;
        begin
            if(x>=origin_x && x<origin_x+characters*(ascii!=0 ? 8 : 16)*scale &&
               y>=origin_y && y<origin_y+16*scale)begin
                dx=x-origin_x;dy=y-origin_y;text_enable=1;
                character_index=ascii!=0 ? (scale==2 ? dx>>4 : dx>>3) : (scale==2 ? dx>>5 : dx>>4);
                message_address={message_id,character_index};numeric_glyph=0;
                font_row=scale==2 ? dy[4:1] : dy[3:0];font_col=scale==2 ? dx[4:1] : (ascii!=0 ? {1'b0,dx[2:0]} : dx[3:0]);
            end
        end
    endtask
    task score_digits;
        input integer ox,oy;
        reg [8:0] dx;
        begin if(x>=ox && x<ox+40 && y>=oy && y<oy+16)begin
            dx=x-ox;text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+score_bcd[(4-(dx>>3))*4+:4];
            font_row=y-oy;font_col={1'b0,dx[2:0]};end end
    endtask
    task pair_digits;
        input integer ox,oy;input [11:0] value;
        reg [8:0] dx;reg [3:0] digit;
        begin if(x>=ox && x<ox+24 && y>=oy && y<oy+16)begin
            dx=x-ox;
            case(dx>>3)0:digit=value[11:8];1:digit=value[7:4];default:digit=value[3:0];endcase
            text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+digit;font_row=y-oy;font_col={1'b0,dx[2:0]};end end
    endtask
    always @*begin
        background={6'd3,6'd5,6'd10};text_enable=0;glyph=0;message_address=0;numeric_glyph=0;font_row=0;font_col=0;
        lane=y<68 ? 0 : y<136 ? 1 : y<204 ? 2 : 3;
        // Explicit four-way muxes avoid DSP inference for lane*68 / lane*3.
        case(lane)
            0:begin lane_origin=0;lane_judgement=game_snapshot[222:220];end
            1:begin lane_origin=68;lane_judgement=game_snapshot[225:223];end
            2:begin lane_origin=136;lane_judgement=game_snapshot[228:226];end
            3:begin lane_origin=204;lane_judgement=game_snapshot[231:229];end
        endcase
        local_y=y-(lane==0 ? 0 : lane==1 ? 68 : lane==2 ? 136 : 204);
        head_hits=0;tail_hits=0;centre=0;tail_end=0;slot=0;
        // Keep the backdrop steady. The former modulo-32 sparkles looked
        // like a flashing dot matrix on the physical panel.
        case(display_page)
            0:begin
                label(0,176,24,4,2,0);
                if(y>=94 && y<=227)begin
                    if(x>=24 && x<=227 && !(y<102 && (x<32 || x>219)) && !(y>219 && (x<32 || x>219)))begin
                        background={6'd5,6'd18+y[5:3],6'd35+x[5:3]};
                        if(x<28 || x>223 || y<98 || y>223)background={6'd8,6'd30+{1'b0,breath},6'd63};
                    end
                    if(x>=252 && x<=455 && !(y<102 && (x<260 || x>447)) && !(y>219 && (x<260 || x>447)))begin
                        background={6'd28+y[5:3],6'd8+x[5:3],6'd35};
                        if(x<256 || x>451 || y<98 || y>223)background={6'd50,6'd15+{1'b0,breath},6'd52};
                    end
                end
                label(1,94,144,4,1,0);label(2,322,144,4,1,0);
                label(26,94,181,4,1,0);label(27,322,181,4,1,0);
            end
            2:begin
                label(3,176,6,4,2,0);label(17,24,14,2,1,0);
                if(x>=24 && x<=455 && y>=48)begin
                    background=y<92 ? {6'd6,6'd23,6'd36} : {6'd6,6'd9,6'd16};
                    if(y==48 || y==91 || y==135 || y==179 || y==223 || y==267)background={6'd12,6'd23,6'd35};
                end
                label(4,56,60,3,1,0);label(24,268,60,5,1,0);
                label(5,56,104,3,1,0);label(5,56,148,3,1,0);label(5,56,192,3,1,0);label(5,56,236,3,1,0);
            end
            3:begin
                label(6,176,20,4,2,0);label(17,24,14,2,1,0);label(4,216,70,3,1,0);
                label(25,184,170,6,1,0);
                if(x>=64 && x<416 && y>=104 && y<144)begin
                    if(x<152)background={6'd12,6'd29,6'd60};
                    else if(x<240)background={6'd4,6'd44,6'd33};
                    else if(x<328)background={6'd61,6'd30,6'd4};
                    else background={6'd59,6'd8,6'd15};
                end
                if(y>=198 && y<=252)begin
                    if(x>=40 && x<230)background={6'd6,6'd33,6'd47};
                    else if(x>=250 && x<=440)background=ALLOW_AUTOPLAY_PREVIEW ? {6'd35,6'd17,6'd44} : {6'd8,6'd9,6'd11};
                end
                label(7,102,208,2,2,0);label(8,310,208,2,2,0);
            end
            4,5:begin
                background=lane==0 ? {6'd3,6'd6,6'd16} : lane==1 ? {6'd2,6'd13,6'd11} :
                           lane==2 ? {6'd15,6'd8,6'd2} : {6'd16,6'd3,6'd6};
                if(local_y==0 || local_y==67)background={6'd12,6'd17,6'd22};
                if(x<80)background={6'd3,6'd5,6'd9};
                if(x>=94 && x<=98)background={6'd42,6'd48,6'd63};
                for(k=0;k<8;k=k+1)begin
                    slot={lane,3'd0}+k;centre=centres[slot*12+:12];tail_end=centre+20+tails[slot*9+:9];
                    head_hits[k]=valid_blocks[slot] && {3'd0,x}+20>=centre && {3'd0,x}<=centre+20 &&
                        local_y>=14 && local_y<=53 && !((local_y<18 || local_y>49) &&
                        ({3'd0,x}+16<centre || {3'd0,x}>centre+16));
                    tail_hits[k]=valid_blocks[slot] && {3'd0,x}>centre+20 && {3'd0,x}<tail_end && local_y>=29 && local_y<=37;
                end
                label(19,10,5,5,1,1);score_digits(10,25);
                label(20,10,73,5,1,1);pair_digits(18,93,number_bcd[11:0]);
                label(21,10,141,3,1,1);pair_digits(18,161,number_bcd[23:12]);
                label(22,10,209,3,1,1);pair_digits(18,229,number_bcd[35:24]);
                case(lane_judgement)
                    1:label(28,116,lane_origin+3,7,1,1);
                    2:label(29,116,lane_origin+3,4,1,1);
                    3:label(30,116,lane_origin+3,3,1,1);
                    4:label(23,116,lane_origin+3,4,1,1);
                    5:label(31,116,lane_origin+3,5,1,1);
                endcase
                if(display_page==4)begin
                    label(7,208,116,2,2,0);
                    if(x>=286 && x<294 && y>=126 && y<142)begin
                        text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+(game_snapshot[159] && $signed(game_snapshot[159:128])<-48000 ? 2 : 1);
                        font_row=y-126;font_col=x-286;
                    end
                end
            end
            6:begin
                label(11,176,18,4,2,0);label(4,216,67,3,1,0);
                label(19,100,105,5,1,1);score_digits(100,126);
                label(21,268,105,3,1,1);pair_digits(268,126,number_bcd[23:12]);
                label(22,100,161,3,1,1);pair_digits(140,161,number_bcd[35:24]);
                label(23,268,161,4,1,1);pair_digits(308,161,number_bcd[47:36]);
                if(y>=208 && y<=260)begin
                    if(x>=24 && x<160)background={6'd6,6'd29,6'd38};
                    else if(x>=172 && x<308)background={6'd25,6'd14,6'd35};
                    else if(x>=320 && x<=456)background={6'd13,6'd19,6'd32};
                end
                label(12,76,225,2,1,0);label(13,216,225,2,1,0);label(14,372,225,2,1,0);
            end
        endcase
        if(!touch_ready && display_page==1)label(15,320,252,5,1,0);
        if(transition)label(18,216,248,3,1,0);
    end
    reg [6:0] glyph1;
    wire [6:0] message_glyph;
    reg numeric1;
    reg [3:0] row1,col1,col2;
    reg en1,en2,en3,ink3;
    wire [15:0] font_bits;
    reg [17:0] bg1,bg2,bg3;
    reg [1:0] lane1,lane2;
    reg [7:0] heads1,tails1;
    reg head2,tail2;
    game_message_rom u_message(.clk(clk),.address(message_address),.glyph(message_glyph));
    game_font_rom u_font(.clk(clk),.glyph(numeric1 ? glyph1 : message_glyph),.row(row1),.bits(font_bits));
    always @(posedge clk)begin
        if(!rst_n)begin rgb<=0;glyph1<=0;numeric1<=0;row1<=0;col1<=0;col2<=0;
            en1<=0;en2<=0;en3<=0;ink3<=0;bg1<=0;bg2<=0;bg3<=0;
            lane1<=0;lane2<=0;heads1<=0;tails1<=0;head2<=0;tail2<=0;end
        else begin
            glyph1<=glyph;numeric1<=numeric_glyph;row1<=font_row;col1<=font_col;col2<=col1;
            en1<=text_enable;en2<=en1;en3<=en2;ink3<=font_bits[15-col2];
            bg1<=background;bg2<=bg1;bg3<=bg2;lane1<=lane;lane2<=lane1;
            heads1<=head_hits;tails1<=tail_hits;head2<=|heads1;tail2<=|tails1;
            if(head2)case(lane2)
                0:bg3<={6'd15,6'd35,6'd63};1:bg3<={6'd6,6'd57,6'd42};
                2:bg3<={6'd63,6'd33,6'd5};3:bg3<={6'd62,6'd12,6'd23};
            endcase
            else if(tail2)case(lane2)
                0:bg3<={6'd8,6'd20,6'd38};1:bg3<={6'd4,6'd32,6'd25};
                2:bg3<={6'd39,6'd20,6'd3};3:bg3<={6'd37,6'd8,6'd14};
            endcase
            rgb<=en3 && ink3 ? {6'd58,6'd62,6'd63} : bg3;
        end
    end
endmodule
