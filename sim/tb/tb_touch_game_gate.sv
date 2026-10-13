`timescale 1ns/1ps
// Compare actual synthesized GPIO/LCD/audio outputs to the complete RTL top.
// No touch slave is connected: initial menu, reset sequencing and silent audio.
module tb_touch_game_gate;
    reg audio_clk=0,sys_clk=0;
    always #40.690104 audio_clk=~audio_clk;
    always #10 sys_clk=~sys_clk;
    tri1 gscl,gsda,gint,rscl,rsda,rint;
    tri [3:0] grow,rrow;
    wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl,grst,rrst;
    wire [5:0] gr,gg,gb,rr,rg,rb;
    wire [6:0] gaudio,raudio;
    `define PORTS .audio_clk_12m288(audio_clk),.sys_clk_50m(sys_clk), \
        .USER_BUTTON1_n(1'b1),.USER_BUTTON2_n(1'b1),.USER_BUTTON3_n(1'b1), \
        .COL0(1'b1),.COL1(1'b1),.COL2(1'b1),.COL3(1'b1), \
        .COL4(1'b1),.COL5(1'b1),.COL6(1'b1),.COL7(1'b1), \
        .adc_cs_n(),.adc_sclk(),.adc_mosi(),.adc_miso(1'b0),.event_led()
    neo_guitar_touch_game_top gate(`PORTS,
        .ROW0(grow[0]),.ROW1(grow[1]),.ROW2(grow[2]),.ROW3(grow[3]),
        .dac_bclk(gaudio[0]),.dac_lrck(gaudio[1]),.dac_din(gaudio[2]),.pa_en_n(gaudio[3]),
        .i2s_bclk(gaudio[4]),.i2s_ws(gaudio[5]),.i2s_data(gaudio[6]),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),
        .lcd_r(gr),.lcd_g(gg),.lcd_b(gb),.ctp_scl(gscl),.ctp_sda(gsda),.ctp_int(gint),.ctp_rst_n(grst));
    rtlref_neo_guitar_touch_game_top reference(`PORTS,
        .ROW0(rrow[0]),.ROW1(rrow[1]),.ROW2(rrow[2]),.ROW3(rrow[3]),
        .dac_bclk(raudio[0]),.dac_lrck(raudio[1]),.dac_din(raudio[2]),.pa_en_n(raudio[3]),
        .i2s_bclk(raudio[4]),.i2s_ws(raudio[5]),.i2s_data(raudio[6]),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),
        .lcd_r(rr),.lcd_g(rg),.lcd_b(rb),.ctp_scl(rscl),.ctp_sda(rsda),.ctp_int(rint),.ctp_rst_n(rrst));
    integer clocks=0,pixels=0;
    always @(posedge sys_clk)begin
        #2;
        if(reference.u_display.initialized)begin
            clocks=clocks+1;
            if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})
                $fatal(1,"FAIL: synthesized menu LCD mismatch at clock %0d",clocks);
            if({gscl,gsda,gint,grst}!=={rscl,rsda,rint,rrst})
                $fatal(1,"FAIL: synthesized touch GPIO mismatch");
        end
    end
    always @(posedge audio_clk)begin
        #2;if(reference.audio_rst_n && gaudio!==raudio)$fatal(1,"FAIL: synthesized audio pin mismatch");
    end
    always @(posedge gp)if(gd)begin
        pixels=pixels+1;
        if(pixels==480*272*3)begin
            $display("PASS: synthesized menu LCD %0d clocks / %0d pixels, touch reset GPIO and silent PT8211/I2S pins match full RTL",clocks,pixels);
            $finish;
        end
    end
    initial begin #100000000;$fatal(1,"FAIL: gate menu watchdog");end
endmodule
