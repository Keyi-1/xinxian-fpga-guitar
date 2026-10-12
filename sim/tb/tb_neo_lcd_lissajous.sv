`timescale 1ns/1ps
module tb_neo_lcd_lissajous;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=1,mode_n=1,pause_n=1;
    wire pclk,hs,vs,de,bl;
    wire [5:0] r,g,b;
    neo_lcd_lissajous_top #(.STARTUP_CYCLES(16),
        .KEY_DEBOUNCE_CYCLES(8),.AUTO_MODE_FRAMES(4)) dut(
        .sys_clk(clk),.sys_rst_n(reset_n),.key_pattern_n(mode_n),
        .key_pause_n(pause_n),.lcd_pclk(pclk),.lcd_hsync(hs),
        .lcd_vsync(vs),.lcd_de(de),.lcd_r(r),.lcd_g(g),.lcd_b(b),.lcd_backlight(bl));
    time last_change=0;
    always @(r or g or b or hs or vs or de) last_change=$time;
    reg previous_bank=0;
    integer writes=0;
    always @(posedge clk) begin
        #1;
        if(dut.run_n && dut.initialized) begin
            if(dut.u_renderer.front_bank != previous_bank && de)
                $fatal(1,"FAIL: bank swapped during visible pixels");
            previous_bank=dut.u_renderer.front_bank;
            if(dut.u_renderer.back_we) begin
                writes=writes+1;
                if(dut.u_renderer.back_addr>=130560)
                    $fatal(1,"FAIL: render write outside panel");
                if(dut.u_renderer.state==9 &&
                   (dut.u_renderer.brush_x<0 || dut.u_renderer.brush_x>=480 ||
                    dut.u_renderer.brush_y<0 || dut.u_renderer.brush_y>=272))
                    $fatal(1,"FAIL: brush coordinates outside panel");
            end
        end else previous_bank=0;
    end

    task automatic capture(input string name,output reg [31:0] digest);
        integer i,h,v,visible,lines,line_pixels,bright,f;
        reg expected_de;
        time prior;
        begin
            @(negedge vs); @(posedge pclk); #1;
            f=0;
            if(name!="") begin
                f=$fopen(name,"w");
                if(!f) $fatal(1,"FAIL: PPM output");
                $fwrite(f,"P3\n480 272\n255\n");
            end
            digest=0; visible=0; lines=0; line_pixels=0; bright=0; prior=0;
            for(i=0;i<531*292;i=i+1) begin
                if(i!=0) begin @(posedge pclk); #1; end
                h=i%531; v=i/531;
                if(prior!=0 && $time-prior!=120) $fatal(1,"FAIL: DCLK period");
                prior=$time;
                if($isunknown({hs,vs,de,r,g,b})) $fatal(1,"FAIL: unknown panel output");
                if(hs !== (h>=4) || vs !== (v>=4)) $fatal(1,"FAIL: sync geometry");
                expected_de=(h>=43 && h<523 && v>=12 && v<284);
                if(de !== expected_de) $fatal(1,"FAIL: DE window");
                if($time-last_change<60) $fatal(1,"FAIL: panel settling below 60 ns");
                if(de) begin
                    visible++; line_pixels++;
                    digest=(digest*32'd16777619)^{14'd0,r,g,b};
                    if(r>20 || g>20 || b>25) bright++;
                    if(f) $fwrite(f,"%0d %0d %0d\n",r*4,g*4,b*4);
                end else if({r,g,b}!==18'd0) $fatal(1,"FAIL: nonblack blanking");
                if(h==530) begin
                    if(v>=12 && v<284) begin
                        if(line_pixels!=480) $fatal(1,"FAIL: active width");
                        lines++;
                    end
                    line_pixels=0;
                end
            end
            if(f) $fclose(f);
            if(visible!=130560 || lines!=272) $fatal(1,"FAIL: frame totals");
            $display("PASS: frame %s geometry/clock/settling pixels=%0d bright=%0d digest=%h mode=%0d phase=%0d paused=%b",
                name,visible,bright,digest,dut.display_mode,dut.display_phase,dut.display_paused);
        end
    endtask
    reg [31:0] boot_hash,first_hash,next_hash,hold_a,hold_b;
    reg [15:0] held_phase;
    reg [1:0] held_mode;
    initial begin
        repeat(12) @(negedge clk);
        if(bl!==0) $fatal(1,"FAIL: startup enabled backlight before RAM clear");
        wait(bl);
        capture("",boot_hash);
        capture("lissajous_3_2.ppm",first_hash);
        if(boot_hash==first_hash) $fatal(1,"FAIL: curve renderer inactive");
        if(dut.display_mode!=0 || dut.display_phase!=0) $fatal(1,"FAIL: initial scene");
        // Single debounced press, no repetition while held. Short bounce ignored.
        mode_n=0; repeat(3) @(negedge clk); mode_n=1;
        repeat(20) @(negedge clk);
        if(dut.mode_request!=0) $fatal(1,"FAIL: mode bounce accepted");
        mode_n=0; repeat(50) @(negedge clk);
        if(dut.mode_request!=1) $fatal(1,"FAIL: held mode key count");
        mode_n=1; repeat(30) @(negedge clk);
        capture("",next_hash);
        capture("lissajous_5_4.ppm",next_hash);
        if(first_hash==next_hash || dut.display_mode!=1) $fatal(1,"FAIL: mode or color animation");
        capture("",next_hash);
        capture("lissajous_auto.ppm",next_hash);
        if(dut.display_mode!=2) $fatal(1,"FAIL: automatic ratio change");
        pause_n=0; repeat(50) @(negedge clk); pause_n=1;
        repeat(30) @(negedge clk);
        capture("",next_hash);
        capture("lissajous_hold.ppm",hold_a);
        held_phase=dut.display_phase; held_mode=dut.display_mode;
        capture("",hold_b);
        if(!dut.display_paused || hold_a!=hold_b || dut.display_phase!=held_phase || dut.display_mode!=held_mode)
            $fatal(1,"FAIL: pause did not freeze entire visible image");
        pause_n=0; repeat(25) @(negedge clk); pause_n=1;
        repeat(30) @(negedge clk);
        capture("",next_hash); capture("",next_hash);
        if(dut.display_paused || next_hash==hold_a || dut.display_phase==held_phase)
            $fatal(1,"FAIL: animation resume");
        reset_n=0; repeat(12) @(negedge clk);
        if(bl!==0 || de!==0 || pclk!==0) $fatal(1,"FAIL: reset/backlight");
        reset_n=1; wait(bl);
        capture("",boot_hash); capture("",next_hash);
        if(next_hash!=first_hash) $fatal(1,"FAIL: deterministic reset recovery");
        $display("PASS: LISSAJOUS 13 full frames, auto/manual mode, button debounce, pause/resume, bank safety, reset; writes=%0d",writes);
        $finish;
    end
    initial begin #350000000; $fatal(1,"FAIL: demo timeout"); end
endmodule
