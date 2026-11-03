`timescale 1ns/1ps
module tb_mpu_diag_top;
    reg clk=0;always #10 clk=~clk;
    tri1 scl,sda;
    wire pclk,hs,vs,de,backlight,pa;
    wire [5:0] r,g,b;
    wire [31:0] writes,bursts;
    neo_mpu6050_lcd_diagnostic_top #(.POWER_MS(1),.RESET_MS(2),.WAKE_MS(1),.RETRY_MS(3)) dut(
        .sys_clk_50m(clk),.imu_scl(scl),.imu_sda(sda),.lcd_pclk(pclk),.lcd_hsync(hs),
        .lcd_vsync(vs),.lcd_de(de),.lcd_backlight(backlight),.lcd_r(r),.lcd_g(g),.lcd_b(b),.pa_en_n(pa));
    mpu_diag_slave slave(.scl(scl),.sda(sda),.rst_n(dut.rst_n),.present(1'b1),.address_high(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.who(8'h70),.nak_stage(3'd0),
        .packet({-16'sd2048,16'd1024,16'd8192,16'hcafe,16'd257,-16'sd4321,16'd0}),.writes(writes),.bursts(bursts));
    integer out,meta,pixels=0,line_pixels=0,lines=0;
    reg prior_de=0;
    time last_pclk=0;
    always @(posedge pclk)begin
        if(last_pclk && $time-last_pclk!=120)$fatal(1,"FAIL: DCLK must be 50MHz/6");
        last_pclk=$time;
    end
    initial begin
        wait(dut.status==7);
        @(posedge dut.frame);repeat(3)@(negedge clk);
        meta=$fopen("lcd_top_snapshot.txt","w");
        $fwrite(meta,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
            dut.screen.a68,dut.screen.a69,dut.screen.v68,dut.screen.v69,
            dut.screen.i68,dut.screen.i69,dut.screen.addr,dut.screen.e68,dut.screen.e69,
            dut.screen.stat,dut.screen.err,dut.screen.st,dut.screen.rno,dut.screen.expv,
            dut.screen.got,dut.screen.cnt,dut.screen.failures,dut.screen.sample_age,dut.screen.iscl,dut.screen.isda,dut.screen.chip);
        $fclose(meta);
        out=$fopen("lcd_diag_top.ppm","w");$fwrite(out,"P3\n480 272\n255\n");
        while(pixels<130560)begin
            @(posedge pclk);#1;
            if(de)begin
                if(!hs || !vs || ^{r,g,b}===1'bx)$fatal(1,"FAIL: active RGB/sync invalid");
                line_pixels=line_pixels+1;pixels=pixels+1;
                $fwrite(out,"%0d %0d %0d\n",r*4,g*4,b*4);
            end else if(prior_de)begin
                if(line_pixels!=480)$fatal(1,"FAIL: active row width %0d",line_pixels);
                lines=lines+1;line_pixels=0;
            end
            prior_de=de;
            if(!backlight || !pa)$fatal(1,"FAIL: LCD backlight / amplifier mute");
        end
        $fclose(out);
        if(lines!=271 || line_pixels!=480)$fatal(1,"FAIL: active frame height");
        if(dut.count<=dut.screen.cnt)$fatal(1,"FAIL: no concurrent sampling during LCD frame");
        $display("PASS: pin-level MPU plus real LCD scan, 130560 active pixels, 120ns DCLK, sampling continues during frame");$finish;
    end
    initial begin #200000000;$fatal(1,"FAIL: top watchdog");end
endmodule
