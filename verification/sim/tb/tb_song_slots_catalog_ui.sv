`timescale 1ns/1ps
module tb_song_slots_catalog_ui;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,click=0;reg [8:0] x=0,y=0;
    reg [4:0] overlay=0;reg [479:0] descriptors=0;
    reg [2:0] slot=0,old_slot=0;
    wire v,p,t,ov,op,ot;wire [10:0] base,old_base;
    wire [11:0] count,old_count;wire [31:0] duration,old_duration,step,old_step;wire [1:0] tone,old_tone;
    game_p3_catalog catalog(.slot(slot),.overlay_valid(overlay),.overlay_data(descriptors),.valid(v),.playable(p),.test_only(t),
        .base(base),.event_count(count),.duration(duration),.progress_step(step),.timbre(tone));
    frozen_game_p3_catalog accepted(.slot(old_slot),.overlay_valid(5'd0),.overlay_data(480'd0),.valid(ov),.playable(op),.test_only(ot),
        .base(old_base),.event_count(old_count),.duration(old_duration),.progress_step(old_step),.timbre(old_tone));
    wire [2:0] page,selected;wire send;wire [1:0] mode;
    touch_game_ui #(.USE_P2(1),.WRITABLE(1)) ui(.clk(clk),.rst_n(rst_n),.tick_ms(1'b0),.touch_ready(1'b1),
        .click(click),.double_click(1'b0),.click_x(x),.click_y(y),.game_snapshot(256'd0),
        .command_busy(1'b0),.command_done(1'b0),.import_busy(1'b0),.overlay_valid(overlay),
        .command_send(send),.command_mode(mode),.selected_slot(selected),.display_fault(1'b0),.page(page),.flush_gesture(),.transition());
    task tap(input integer px,py);
        @(negedge clk);x=px;y=py;click=1;@(negedge clk);click=0;repeat(2)@(negedge clk);
    endtask
    integer mask,s,cases=0;
    reg [95:0] d;
    initial begin
        for(s=0;s<5;s=s+1)descriptors[s*96+:96]={7'd0,2'(s%3),32'(48000*(s+1)),12'(s+1),11'(703+s*8),32'(100*(s+1))};
        repeat(5)@(negedge clk);rst_n=1;tap(340,150);
        for(mask=0;mask<32;mask=mask+1)begin
            overlay=mask;
            for(s=0;s<8;s=s+1)begin
                slot=s;old_slot=s==1 ? 2 : s==2 ? 3 : 0;#2;
                if(s<5 && overlay[s])begin
                    d=descriptors[s*96+:96];
                    if(!v || !p || t || {base,count,duration,tone,step}!=={d[42:32],d[54:43],d[86:55],d[88:87],d[31:0]})
                        $fatal(1,"FAIL: imported descriptor mask%0d slot%0d",mask,s);
                end else if(s<3)begin
                    if({v,p,t,base,count,duration,tone,step}!=={ov,op,ot,old_base,old_count,old_duration,old_tone,old_step})
                        $fatal(1,"FAIL: retained builtin metadata slot%0d",s);
                    if(step!=(duration+479)/480)$fatal(1,"FAIL: remapped progress duration slot%0d",s);
                end else if(v || p || t || base || count || duration || tone || step)$fatal(1,"FAIL: empty/outside slot%0d",s);
                cases=cases+1;
                if(s<5)begin
                    tap(100,70+s*44);
                    if(s<3 || overlay[s])begin
                        if(page!=3 || selected!=s)$fatal(1,"FAIL: selected row mapping mask%0d slot%0d",mask,s);
                        tap(40,20);
                    end else if(page!=2 || send)$fatal(1,"FAIL: empty row starts a song slot%0d",s);
                end
            end
        end
        $display("PASS: %0d catalog cases/all32 overlay masks, retained builtin metadata/progress, first3 playable, slots4/5 empty until independently imported, exact UI row selection",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: slots watchdog");end
endmodule
