`timescale 1ns/1ps
module tb_game_p3_display_equivalence;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst=0,frame=0;reg [2:0] page=0,slot=0;
    reg [8:0] x=511,y=511;
    reg [255:0] snapshot=0;reg [4:0] valid=0;reg [479:0] descriptors=0;
    reg [383:0] centres=0;reg [287:0] tails=0;reg [31:0] blocks=32'h03030303;
    wire [17:0] rgb,reference;wire [2:0] shown,ref_shown;
    integer song,p,px,py,k,pixels=0,scenes=0;
    touch_game_renderer #(.USE_P2(1),.WRITABLE(1)) dut(.imu_status(10'd0),.clk(clk),.rst_n(rst),.frame_start(frame),.page(page),
        .selected_slot(slot),.display_fault(1'b0),.overlay_valid(valid),.overlay_data(descriptors),
        .touch_ready(1'b1),.transition(1'b0),.x(x),.y(y),.centres(centres),.tails(tails),.valid_blocks(blocks),
        .game_snapshot(snapshot),.rgb(rgb),.display_page(shown));
    accepted_p2_renderer #(.USE_P2(1)) frozen(.clk(clk),.rst_n(rst),.frame_start(frame),.page(page),
        .selected_slot(slot),.display_fault(1'b0),.touch_ready(1'b1),.transition(1'b0),.x(x),.y(y),
        .centres(centres),.tails(tails),.valid_blocks(blocks),.game_snapshot(snapshot),.rgb(reference),.display_page(ref_shown));
    task automatic begin_frame;
        begin
            @(negedge clk);x=511;y=511;frame=1;
            @(negedge clk);frame=0;repeat(400)@(negedge clk);
        end
    endtask
    initial begin
        for(k=0;k<32;k=k+1)begin centres[k*12+:12]=96+32*k;tails[k*9+:9]=20+k;end
        repeat(5)@(negedge clk);rst=1;
        for(song=0;song<4;song=song+1)begin
            slot=song;snapshot=0;snapshot[237:235]=song;snapshot[229:228]=2;
            snapshot[95:64]=20000;snapshot[127:96]=1234;snapshot[143:128]=12;snapshot[159:144]=24;
            snapshot[175:160]=34;snapshot[191:176]=5;snapshot[215:204]=12'b010_011_001_000;
            snapshot[227:220]=song+1;
            for(p=0;p<6;p=p+1)if(song!=1)begin
                page=p==0 ? 0 : p==1 ? 2 : p==2 ? 3 : p==3 ? 4 : p==4 ? 5 : 6;
                snapshot[230]=page==4;begin_frame();
                for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                    @(negedge clk);x=px;y=py;repeat(6)@(posedge clk);#1;
                    // The only baseline-menu exception is the user's deleted
                    // slow-practice row. The other three songs stay identical.
                    if(!(page==2 && py>=92 && py<136 && px>=24 && px<=455))begin
                        if(rgb!==reference || shown!==ref_shown)$fatal(1,"FAIL: builtin pixels slot%0d page%0d x%0d y%0d",song,page,px,py);
                        pixels=pixels+1;
                    end
                end
                scenes=scenes+1;
            end
        end
        // Runtime metadata changes only title/progress, never note geometry,
        // gradients, score digits, judgement feedback or the x=96 line.
        valid=31;
        for(song=0;song<4;song=song+1)begin
            slot=song;descriptors[song*96+:96]={7'd0,2'd1,32'd13024,12'd2,11'd703,32'd28};
            snapshot[237:235]=song;snapshot[255:250]=song+10;snapshot[95:64]=0;page=5;begin_frame();
            if(dut.progress_step!=28)$fatal(1,"FAIL: imported progress step");
            for(py=52;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;repeat(6)@(posedge clk);#1;
                if(rgb!==reference)$fatal(1,"FAIL: imported stage geometry/feedback x%0d y%0d",px,py);
                pixels=pixels+1;
            end
            scenes=scenes+1;
        end
        $display("PASS: frozen accepted M2 renderer %0d exact pixels / %0d scenes, all builtin menus/ready/countdown/stage/results; runtime title/progress metadata preserves stage geometry/gradients/feedback and six-clock pixel cadence",pixels,scenes);
        $finish;
    end
    initial begin #500000000;$fatal(1,"FAIL: P3 renderer watchdog");end
endmodule
