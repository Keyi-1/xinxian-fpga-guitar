// Full-width four-lane stage. Four pixel stages fit the six-clock DCLK cadence:
// relative note coordinates, shape selection, palette/font, output.
// No framebuffer, per-pixel divide, blur or added audio processing.
module accepted_p2_renderer #(parameter integer ALLOW_AUTOPLAY_PREVIEW=1,USE_P2=0)
    (input wire clk,rst_n,frame_start,input wire [2:0] page,
    input wire [2:0] selected_slot,input wire display_fault,
    input wire touch_ready,transition,input wire [8:0] x,y,
    input wire [383:0] centres,input wire [287:0] tails,input wire [31:0] valid_blocks,
    input wire [255:0] game_snapshot,output reg [17:0] rgb,output reg [2:0] display_page);
    `include "../config/game_ui_messages_p2.vh"
    `include "../config/game_score_config.vh"
    `include "../config/game_p2_progress.vh"
    localparam integer PROGRESS_STEP=(`GAME_DURATION_SAMPLES+479)/480;
    localparam SCORE_DIGITS=USE_P2 ? 6 : 5, COUNTER_DIGITS=USE_P2 ? 5 : 3;
    localparam BCD_WIDTH=SCORE_DIGITS*4, COUNTER_WIDTH=COUNTER_DIGITS*4;
    wire [31:0] time_value=USE_P2 ? game_snapshot[95:64] : game_snapshot[159:128];
    wire [31:0] score_value=USE_P2 ? game_snapshot[127:96] : {12'd0,game_snapshot[179:160]};
    wire [15:0] combo_value=USE_P2 ? game_snapshot[143:128] : {8'd0,game_snapshot[187:180]};
    wire [15:0] max_value=USE_P2 ? game_snapshot[159:144] : {8'd0,game_snapshot[195:188]};
    wire [15:0] hits_value=USE_P2 ? game_snapshot[175:160] : {8'd0,game_snapshot[203:196]};
    wire [15:0] miss_value=USE_P2 ? game_snapshot[191:176] : {8'd0,game_snapshot[211:204]};
    wire [11:0] judgement_value=USE_P2 ? game_snapshot[219:208] : game_snapshot[231:220];
    wire [7:0] epoch_value=USE_P2 ? game_snapshot[227:220] : game_snapshot[245:238];
    wire [2:0] active_slot=USE_P2 ? game_snapshot[237:235] : 3'd0;
    wire [2:0] title_slot=(display_page==3) ? selected_slot : active_slot;
    wire error_value=USE_P2 && (game_snapshot[233] || display_fault);
    // Generated from the immutable catalogue; no independently maintained times.
    wire [31:0] progress_step=USE_P2 ? game_p2_progress_step(active_slot) : PROGRESS_STEP;
    reg [8:0] progress_identity;
    reg [7:0] animation;
    reg [19:0] score_shift;
    reg [BCD_WIDTH-1:0] bcd_work,score_bcd;
    // One double-dabble engine formats score and all four counters. A complete
    // round takes 105 system clocks, well inside the existing vertical blank.
    // Inputs are the CDC's frame-held snapshot; active-video digits stay stable.
    reg [2:0] number_select;
    reg [4:0] number_step;
    reg [4*COUNTER_WIDTH-1:0] number_bcd;
    reg [BCD_WIDTH-1:0] bcd_adjusted;
    integer d;
    // Geometry and result effects are independent of the audio judgement.
    reg [7:0] feedback_previous;
    reg [15:0] feedback_age;
    reg [1:0] feedback_lane;
    reg [8:0] progress_pixels;
    reg [31:0] progress_threshold;
    integer f;
    wire stage_page=display_page==4 || display_page==5;
    always @(posedge clk)begin
        if(!rst_n)begin
            feedback_previous<=0;feedback_age<=0;feedback_lane<=0;
            progress_pixels<=0;progress_threshold<=progress_step;progress_identity<={active_slot,game_snapshot[255:250]};
        end else if(!stage_page || time_value[31] || (USE_P2 && progress_identity!={active_slot,game_snapshot[255:250]}))begin
            feedback_previous<=epoch_value;feedback_age<=0;
            progress_pixels<=0;progress_threshold<=progress_step;progress_identity<={active_slot,game_snapshot[255:250]};
        end else begin
            for(f=0;f<4;f=f+1)begin
                if(epoch_value[f*2+:2]!=feedback_previous[f*2+:2])begin
                    feedback_previous[f*2+:2]<=epoch_value[f*2+:2];
                    feedback_age[f*4+:4]<=15;feedback_lane<=f;
                end else if(frame_start && feedback_age[f*4+:4]!=0)
                    feedback_age[f*4+:4]<=feedback_age[f*4+:4]-1'b1;
            end
            // Snapshot time changes only in blank. Catch up in <=480 clocks,
            // using one constant increment instead of a pixel-rate divider.
            if(progress_pixels<480 && time_value>=progress_threshold)begin
                progress_pixels<=progress_pixels+1'b1;
                progress_threshold<=progress_threshold+progress_step;
            end
        end
    end
    always @*begin
        bcd_adjusted=bcd_work;
        for(d=0;d<SCORE_DIGITS;d=d+1)if(bcd_work[d*4+:4]>=5)bcd_adjusted[d*4+:4]=bcd_work[d*4+:4]+3;
    end
    always @(posedge clk)begin
        if(!rst_n)begin animation<=0;display_page<=0;score_shift<=0;
            bcd_work<=0;score_bcd<=0;
            number_select<=0;number_step<=0;number_bcd<=0;end
        else begin
            if(frame_start)begin animation<=animation+1'b1;display_page<=page;end
            if(number_step==0)begin
                case(number_select)
                    0:score_shift<=USE_P2 && score_value>999999 ? 20'd999999 : score_value[19:0];
                    1:score_shift<={4'd0,combo_value};
                    2:score_shift<={4'd0,max_value};
                    3:score_shift<={4'd0,hits_value};
                    default:score_shift<={4'd0,miss_value};
                endcase
                bcd_work<=0;number_step<=1;
            end else begin
                score_shift<={score_shift[18:0],1'b0};bcd_work<={bcd_adjusted[BCD_WIDTH-2:0],score_shift[19]};
                if(number_step==20)begin
                    case(number_select)
                        0:score_bcd<={bcd_adjusted[BCD_WIDTH-2:0],score_shift[19]};
                        1:number_bcd[0*COUNTER_WIDTH+:COUNTER_WIDTH]<={bcd_adjusted[COUNTER_WIDTH-2:0],score_shift[19]};
                        2:number_bcd[1*COUNTER_WIDTH+:COUNTER_WIDTH]<={bcd_adjusted[COUNTER_WIDTH-2:0],score_shift[19]};
                        3:number_bcd[2*COUNTER_WIDTH+:COUNTER_WIDTH]<={bcd_adjusted[COUNTER_WIDTH-2:0],score_shift[19]};
                        4:number_bcd[3*COUNTER_WIDTH+:COUNTER_WIDTH]<={bcd_adjusted[COUNTER_WIDTH-2:0],score_shift[19]};
                    endcase
                    number_select<=number_select==4 ? 3'd0 : number_select+1'b1;number_step<=0;
                end else number_step<=number_step+1'b1;
            end
        end
    end
    reg [17:0] background;
    reg [6:0] glyph;
    reg [10:0] message_address;
    reg numeric_glyph;
    reg [3:0] font_row,font_col;
    reg text_enable;
    reg [1:0] lane;
    reg [8:0] lane_origin;
    reg [2:0] lane_judgement;
    reg [3:0] lane_age;
    reg [6:0] local_y;
    reg [79:0] relative_x;
    reg [7:0] note_valid,tail_hits;
    reg signed [9:0] dx_work;
    reg [8:0] centre;
    reg [4:0] slot;
    reg [1:0] text_tint;
    wire [2:0] latest_judgement=feedback_lane==0 ? judgement_value[0+:3] : feedback_lane==1 ? judgement_value[3+:3] :
                                  feedback_lane==2 ? judgement_value[6+:3] : judgement_value[9+:3];
    wire recent_feedback=feedback_age[feedback_lane*4+:4]!=0;
    integer k;
    wire [4:0] breath=animation[5] ? ~animation[4:0] : animation[4:0];
    task label;
        input [5:0] message_id;input integer origin_x,origin_y,characters,scale,ascii;
        reg [8:0] dx,dy;reg [4:0] character_index;
        begin
            if(x>=origin_x && x<origin_x+characters*(ascii!=0 ? 8 : 16)*scale &&
               y>=origin_y && y<origin_y+16*scale)begin
                dx=x-origin_x;dy=y-origin_y;text_enable=1;
                character_index=ascii!=0 ? (scale==2 ? dx>>4 : dx>>3) : (scale==2 ? dx>>5 : dx>>4);
                message_address={message_id,character_index};numeric_glyph=0;
                font_row=scale==2 ? dy[4:1] : dy[3:0];font_col=scale==2 ? (ascii!=0 ? {1'b0,dx[3:1]} : dx[4:1]) : (ascii!=0 ? {1'b0,dx[2:0]} : dx[3:0]);
            end
        end
    endtask
    task score_digits;
        input integer ox,oy,scale;
        reg [8:0] dx,dy;
        begin if(x>=ox && x<ox+SCORE_DIGITS*8*scale && y>=oy && y<oy+16*scale)begin
            dx=x-ox;dy=y-oy;text_enable=1;numeric_glyph=1;
            glyph=`GAME_DIGIT_BASE+score_bcd[(SCORE_DIGITS-1-(scale==2 ? dx>>4 : dx>>3))*4+:4];
            font_row=scale==2 ? dy[4:1] : dy[3:0];
            font_col=scale==2 ? {1'b0,dx[3:1]} : {1'b0,dx[2:0]};end end
    endtask
    task pair_digits;
        input integer ox,oy;input [COUNTER_WIDTH-1:0] value;
        reg [8:0] dx;reg [3:0] digit;
        begin if(x>=ox && x<ox+COUNTER_DIGITS*8 && y>=oy && y<oy+16)begin
            dx=x-ox;
            digit=value[(COUNTER_DIGITS-1-(dx>>3))*4+:4];
            text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+digit;font_row=y-oy;font_col={1'b0,dx[2:0]};end end
    endtask
    task combo_digits;
        reg [8:0] dx,dy;reg [3:0] digit;
        begin if(USE_P2 && combo_value>=1000)pair_digits(352,16,number_bcd[0+:COUNTER_WIDTH]);
        else if(x>=352 && x<400 && y>=8 && y<40)begin
            dx=x-352;dy=y-8;
            case(dx>>4)0:digit=number_bcd[11:8];1:digit=number_bcd[7:4];default:digit=number_bcd[3:0];endcase
            if((dx>>4)==2 || ((dx>>4)==1 && number_bcd[11:4]!=0) || digit!=0)begin
                text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+digit;
                font_row=dy[4:1];font_col={1'b0,dx[3:1]};
            end
        end end
    endtask
    task song_title;
        input [2:0] song;input integer ox,oy,scale;
        begin case(song)
            1:label(42,ox,oy,2,scale,0);
            2:if(scale==1)label(55,ox,oy,17,1,1);else label(43,ox,oy,4,scale,1);
            3:label(52,ox,oy,2,scale,0);
            default:label(4,ox,oy,3,scale,0);
        endcase end
    endtask
    task stage_title;
        reg [8:0] dx,dy;reg [1:0] character;
        begin if(x>=16 && x<88 && y>=4 && y<28)begin
            character=x<40 ? 0 : x<64 ? 1 : 2;
            dx=x-(x<40 ? 16 : x<64 ? 40 : 64);dy=y-4;
            text_enable=1;numeric_glyph=1;
            glyph=`GAME_TITLE_TILE_BASE+{character,2'b00}+{dy[4],dx[4]};
            font_row=dy[3:0];font_col=dx[3:0];
        end end
    endtask
    always @*begin
        background={6'd3,6'd5,6'd10};text_enable=0;glyph=0;message_address=0;numeric_glyph=0;font_row=0;font_col=0;text_tint=0;
        lane=y<112 ? 0 : y<160 ? 1 : y<208 ? 2 : 3;
        case(lane)
            0:begin lane_origin=64;lane_judgement=judgement_value[0+:3];lane_age=feedback_age[3:0];end
            1:begin lane_origin=112;lane_judgement=judgement_value[3+:3];lane_age=feedback_age[7:4];end
            2:begin lane_origin=160;lane_judgement=judgement_value[6+:3];lane_age=feedback_age[11:8];end
            3:begin lane_origin=208;lane_judgement=judgement_value[9+:3];lane_age=feedback_age[15:12];end
        endcase
        local_y=y-lane_origin;
        relative_x=0;note_valid=0;tail_hits=0;centre=0;dx_work=0;slot=0;
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
                    background=y<(USE_P2 ? 224 : 92) ? {6'd6,6'd23,6'd36} : {6'd6,6'd9,6'd16};
                    if(y==48 || y==91 || y==135 || y==179 || y==223 || y==267)background={6'd12,6'd23,6'd35};
                end
                label(4,56,60,3,1,0);label(USE_P2 ? 48 : 24,268,60,USE_P2 ? 12 : 5,1,USE_P2);
                if(USE_P2)begin
                    song_title(1,56,104,1);label(46,268,104,13,1,1);
                    song_title(2,56,148,1);label(47,268,148,10,1,1);
                    song_title(3,56,192,1);label(46,268,192,13,1,1);
                    label(45,56,236,9,1,1);
                end else begin label(5,56,104,3,1,0);label(5,56,148,3,1,0);label(5,56,192,3,1,0);label(5,56,236,3,1,0);end
            end
            3:begin
                label(6,176,20,4,2,0);label(17,24,14,2,1,0);song_title(USE_P2 ? selected_slot : 3'd0,USE_P2 && selected_slot==3 ? 224 : 192,70,1);
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
                background={6'd2,6'd4,6'd8};
                if(y<48)background={6'd4,6'd7,6'd12};
                if(x>=345 && x<465 && y>=7 && y<41 && !((y<10 || y>37) && (x<348 || x>461)))
                    background={6'd5,6'd8,6'd13};
                if(y>=48 && y<51)background=x<progress_pixels ? {6'd45,6'd60,6'd63} : {6'd9,6'd13,6'd19};
                if(y>=64 && y<250 && local_y<42)begin
                    if(x>=12 && x<468 && !((local_y<3 || local_y>38) && (x<15 || x>464)))
                        background={6'd5,6'd8,6'd13};
                    if(local_y==20 && x>=12 && x<468)background={6'd8,6'd12,6'd17};
                    if(x>=18 && x<45 && local_y>=8 && local_y<34)case(lane)
                        0:background={6'd6,6'd12,6'd22};1:background={6'd4,6'd16,6'd18};
                        2:background={6'd16,6'd13,6'd13};3:background={6'd16,6'd10,6'd18};
                    endcase
                    if(x>=27 && x<35 && local_y>=13 && local_y<29)begin
                        text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+lane+1'b1;
                        font_row=local_y-13;font_col=x-27;
                    end
                    for(k=0;k<8;k=k+1)begin
                        slot={lane,3'd0}+k;
                        // Layout guarantees 67..500; its unused high bits
                        // need not participate in eight pixel subtractors.
                        centre=centres[slot*12+:9];
                        dx_work=$signed({1'b0,x})-$signed({1'b0,centre});
                        relative_x[k*10+:10]=dx_work;
                        note_valid[k]=valid_blocks[slot] && x>=64;
                        tail_hits[k]=note_valid[k] && dx_work>=14 &&
                            dx_work<$signed(10'd14+{1'b0,tails[slot*9+:9]}) && local_y>=15 && local_y<27;
                    end
                end
                if(y>=60 && y<254)begin
                    if(x==168 || x==240 || x==312 || x==384 || x==456)background={6'd8,6'd12,6'd18};
                    if(x>=89 && x<103)background={6'd6,6'd11,6'd16};
                    if(x==95 || x==96)background={6'd42,6'd56,6'd61};
                    if(y>=64 && y<250 && local_y<42 && lane_age>=11 && x>=92 && x<100)
                        background=lane_judgement==1 || lane_judgement==2 ? {6'd52,6'd61,6'd63} : {6'd63,6'd25,6'd31};
                end
                if(x>=91 && x<101 && ((y>=57 && y<60)||(y>=254 && y<257)))background={6'd45,6'd60,6'd63};
                if(!USE_P2 || active_slot==0)begin stage_title();label(34,16,32,3,1,0);label(35,88,32,6,1,1);end
                else begin
                    if(active_slot==3)label(52,16,0,2,2,0);else song_title(active_slot,16,0,2);label(active_slot==1 ? 51 : active_slot==2 ? 50 : 57,16,32,10,1,1);
                    label(54,104,16,6,1,1);
                end
                label(32,228,0,2,1,0);score_digits(228,16,2);combo_digits();label(33,416,14,2,1,0);
                if(recent_feedback)case(latest_judgement)
                    1:label(39,109,256,12,1,1);2:label(40,109,256,8,1,1);3:label(41,109,256,7,1,1);
                    4:label(23,109,256,4,1,1);5:label(31,109,256,5,1,1);
                    default:label(37,109,256,4,1,0);
                endcase else label(37,109,256,4,1,0);
                label(36,400,256,4,1,0);
                if((y>=32 && y<48 && x<200)||(y<16 && x>=228 && x<260)||(y>=256 && x>=320))text_tint=1;
                if(y>=256 && x>=109 && x<220 && recent_feedback)text_tint=latest_judgement<=2 ? 2 : 3;
                if(display_page==4)begin
                    label(7,208,116,2,2,0);
                    if(x>=286 && x<294 && y>=126 && y<142)begin
                        text_enable=1;numeric_glyph=1;glyph=`GAME_DIGIT_BASE+(time_value[31] && $signed(time_value)<-48000 ? 2 : 1);
                        font_row=y-126;font_col=x-286;
                    end
                end
            end
            6:begin
                label(11,176,18,4,2,0);song_title(active_slot,USE_P2 && active_slot==3 ? 224 : 192,67,1);
                if(error_value)label(53,208,88,5,1,1);
                label(19,100,105,5,1,1);score_digits(100,126,1);
                label(21,268,105,3,1,1);pair_digits(268,126,number_bcd[1*COUNTER_WIDTH+:COUNTER_WIDTH]);
                label(22,100,161,3,1,1);pair_digits(140,161,number_bcd[2*COUNTER_WIDTH+:COUNTER_WIDTH]);
                label(23,268,161,4,1,1);pair_digits(308,161,number_bcd[3*COUNTER_WIDTH+:COUNTER_WIDTH]);
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
    reg [1:0] lane1,lane2,tint1,tint2,tint3;
    reg [6:0] local1;
    reg [79:0] dx1;
    reg [7:0] valid1,tails1;
    reg [2:0] effect2,effect_next;
    reg [7:0] head_mask,shine_mask,shade_mask,halo_mask,tail_bright,tail_mid,tail_soft;
    reg signed [9:0] shape_x;
    integer h;
    always @*begin
        head_mask=0;shine_mask=0;shade_mask=0;halo_mask=0;tail_bright=0;tail_mid=0;tail_soft=0;shape_x=0;
        for(h=0;h<8;h=h+1)begin
            shape_x=$signed(dx1[h*10+:10]);
            head_mask[h]=valid1[h] && shape_x>=-14 && shape_x<14 && local1>=8 && local1<34 &&
                !((local1<10 || local1>31) && (shape_x< -11 || shape_x>10));
            shine_mask[h]=head_mask[h] && shape_x>=-10 && shape_x<10 && local1>=11 && local1<13;
            shade_mask[h]=head_mask[h] && shape_x>=-11 && shape_x<11 && local1>=30 && local1<32;
            halo_mask[h]=valid1[h] && shape_x>=-18 && shape_x<18 && local1>=4 && local1<38;
            tail_bright[h]=tails1[h] && shape_x<32;
            tail_mid[h]=tails1[h] && shape_x<64;
            tail_soft[h]=tails1[h] && shape_x<96;
        end
        effect_next=0;
        if(|head_mask)effect_next=|shine_mask ? 5 : |shade_mask ? 6 : 4;
        else if(|tails1)effect_next=|tail_bright ? 7 : |tail_mid ? 3 : |tail_soft ? 2 : 1;
        else if(|halo_mask)effect_next=1;
    end
    game_message_rom u_message(.clk(clk),.address(message_address),.glyph(message_glyph));
    game_font_rom u_font(.clk(clk),.glyph(numeric1 ? glyph1 : message_glyph),.row(row1),.bits(font_bits));
    always @(posedge clk)begin
        if(!rst_n)begin rgb<=0;glyph1<=0;numeric1<=0;row1<=0;col1<=0;col2<=0;
            en1<=0;en2<=0;en3<=0;ink3<=0;bg1<=0;bg2<=0;bg3<=0;
            lane1<=0;lane2<=0;tint1<=0;tint2<=0;tint3<=0;local1<=0;dx1<=0;valid1<=0;tails1<=0;effect2<=0;end
        else begin
            glyph1<=glyph;numeric1<=numeric_glyph;row1<=font_row;col1<=font_col;col2<=col1;
            en1<=text_enable;en2<=en1;en3<=en2;ink3<=font_bits[15-col2];
            bg1<=background;bg2<=bg1;bg3<=bg2;lane1<=lane;lane2<=lane1;
            tint1<=text_tint;tint2<=tint1;tint3<=tint2;
            dx1<=relative_x;valid1<=note_valid;local1<=local_y;tails1<=tail_hits;effect2<=effect_next;
            case({lane2,effect2})
                5'b00001:bg3<={6'd6,6'd12,6'd21};5'b00010:bg3<={6'd7,6'd17,6'd29};
                5'b00011:bg3<={6'd10,6'd22,6'd37};5'b00111:bg3<={6'd12,6'd28,6'd47};
                5'b00100:bg3<={6'd16,6'd38,6'd63};5'b00101:bg3<={6'd39,6'd50,6'd63};5'b00110:bg3<={6'd12,6'd29,6'd49};
                5'b01001:bg3<={6'd4,6'd15,6'd17};5'b01010:bg3<={6'd4,6'd21,6'd21};
                5'b01011:bg3<={6'd5,6'd29,6'd26};5'b01111:bg3<={6'd6,6'd38,6'd32};
                5'b01100:bg3<={6'd7,6'd54,6'd43};5'b01101:bg3<={6'd35,6'd58,6'd52};5'b01110:bg3<={6'd5,6'd42,6'd34};
                5'b10001:bg3<={6'd17,6'd14,6'd13};5'b10010:bg3<={6'd25,6'd19,6'd14};
                5'b10011:bg3<={6'd35,6'd25,6'd15};5'b10111:bg3<={6'd46,6'd32,6'd16};
                5'b10100:bg3<={6'd63,6'd43,6'd17};5'b10101:bg3<={6'd63,6'd53,6'd40};5'b10110:bg3<={6'd49,6'd33,6'd13};
                5'b11001:bg3<={6'd17,6'd11,6'd16};5'b11010:bg3<={6'd25,6'd13,6'd19};
                5'b11011:bg3<={6'd35,6'd17,6'd23};5'b11111:bg3<={6'd46,6'd21,6'd27};
                5'b11100:bg3<={6'd63,6'd26,6'd32};5'b11101:bg3<={6'd63,6'd44,6'd47};5'b11110:bg3<={6'd49,6'd20,6'd25};
            endcase
            if(en3 && ink3)case(tint3)
                1:rgb<={6'd41,6'd45,6'd52};2:rgb<={6'd63,6'd55,6'd32};3:rgb<={6'd63,6'd27,6'd31};
                default:rgb<={6'd58,6'd62,6'd63};
            endcase else rgb<=bg3;
        end
    end
endmodule
