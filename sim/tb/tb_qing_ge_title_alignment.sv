`timescale 1ns/1ps
// Independent frozen-M1 pixel comparison, with only the requested title boxes
// allowed to change. Expected two glyphs come directly from the frozen font.
module tb_qing_ge_title_alignment;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #10 clk=~clk;
    reg rst=0,frame=0;reg [2:0] page=3,selected=3;
    reg [255:0] snapshot=0;reg [8:0] x=0,y=0;
    wire [17:0] now_rgb,old_rgb,legacy_now,legacy_old;
    reg [15:0] font[0:2047];
    integer p,s,px,py,frames=0,pixels=0,left,top,old_left,old_width,fd;
    reg changed,in_title_box;reg [17:0] expected;
`define ARGS .clk(clk),.rst_n(rst),.frame_start(frame),.page(page),.selected_slot(selected), \
    .display_fault(1'b0),.touch_ready(1'b1),.transition(1'b0),.x(x),.y(y), \
    .centres(384'd0),.tails(288'd0),.valid_blocks(32'd0),.game_snapshot(snapshot),.display_page()
    touch_game_renderer #(.USE_P2(1)) dut(`ARGS,.rgb(now_rgb));
    touch_game_renderer_m1 #(.USE_P2(1)) frozen(`ARGS,.rgb(old_rgb));
    touch_game_renderer #(.USE_P2(0)) legacy_dut(`ARGS,.rgb(legacy_now));
    touch_game_renderer_m1 #(.USE_P2(0)) legacy_frozen(`ARGS,.rgb(legacy_old));
`undef ARGS
    initial begin
        $readmemh("../../../mem/game_font_16.mem",font);
        repeat(8)@(negedge clk);rst=1;
        for(p=2;p<=6;p=p+1)for(s=0;s<4;s=s+1)begin
            page=p;selected=s;snapshot=0;snapshot[237:235]=s;
            frame=1;@(negedge clk);frame=0;repeat(250)@(negedge clk);
            changed=p==2 || (s==3 && (p==3 || p==6));
            left=p==2 ? 56 : 224;top=p==2 ? 192 : p==3 ? 70 : 67;
            old_left=p==2 ? 56 : 192;old_width=64;
            fd=0;if(s==3 && (p==2 || p==3 || p==6))begin
                fd=$fopen($sformatf("qing_ge_title_page_%0d.ppm",p),"w");$fwrite(fd,"P3\n480 272\n63\n");
            end
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;repeat(5)@(negedge clk);
                if(^now_rgb===1'bx || legacy_now!==legacy_old)$fatal(1,"FAIL: title unknown/legacy changed");
                in_title_box=changed && px>=old_left && px<old_left+old_width && py>=top && py<top+16;
                if(!in_title_box && now_rgb!==old_rgb)$fatal(1,"FAIL: unrelated title pixel changed page=%0d slot=%0d xy=%0d,%0d",p,s,px,py);
                if(in_title_box)begin
                    expected=p==2 ? {6'd6,6'd23,6'd36} : {6'd3,6'd5,6'd10};
                    if(px>=left && px<left+32 && font[(px<left+16 ? 70 : 71)*16+py-top][15-((px-left)%16)])
                        expected={6'd58,6'd62,6'd63};
                    if(now_rgb!==expected)$fatal(1,"FAIL: expected centered two-glyph Qing Ge title page=%0d xy=%0d,%0d RGB=%h/%h",p,px,py,now_rgb,expected);
                end
                if(fd)$fwrite(fd,"%0d %0d %0d\n",now_rgb[17:12],now_rgb[11:6],now_rgb[5:0]);
                pixels=pixels+1;
            end
            if(fd)$fclose(fd);frames=frames+1;
        end
        $display("PASS: Qing Ge two-glyph title, ready/results x224..255 centered on 480; menu column x56, stage unchanged; %0d screens/%0d pixels at six-clock cadence; all pixels outside requested title boxes and legacy mode equal frozen M1",frames,pixels);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: title alignment watchdog");end
endmodule
