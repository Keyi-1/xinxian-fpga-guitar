`timescale 1ns/1ps
// Compare actual synthesized GPIO/LCD/audio outputs to the complete RTL top.
// Display-only snapshots exercise the real full-width synthesized renderer.
// LCD coordinates are never forced: all pixels use the physical scan cadence.
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
    reg [2:0] test_page=0;
    reg [255:0] test_snapshot=0;
    wire test_update=reference.u_display.frame_start;
    integer frames=0,clocks=0,pixels=0;
    initial begin
        `include "stage_force.vh"
    end
    always @(posedge sys_clk)begin
        #2;
        if(reference.u_display.initialized)begin
            clocks=clocks+1;
            if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})
                $fatal(1,"FAIL: synthesized menu LCD mismatch at clock %0d",clocks);
            if({gscl,gsda,gint,grst}!=={rscl,rsda,rint,rrst})
                $fatal(1,"FAIL: synthesized touch GPIO mismatch");
            if(reference.u_display.frame_start)begin
                frames=frames+1;
                case(frames)
                    2:begin test_page=4;test_snapshot[159:128]=-96000;end
                    3:begin
                        test_page=5;test_snapshot[159:128]=24000;
                        test_snapshot[179:160]=1270;test_snapshot[187:180]=12;
                        test_snapshot[195:188]=18;test_snapshot[203:196]=23;
                        test_snapshot[222:220]=1;test_snapshot[239:238]=1;
                    end
                    4:begin
                        test_snapshot[159:128]=48000;test_snapshot[179:160]=1370;
                        test_snapshot[187:180]=13;test_snapshot[239:238]=2;
                    end
                    5:begin
                        test_snapshot[159:128]=72000;test_snapshot[179:160]=1440;
                        test_snapshot[187:180]=14;test_snapshot[225:223]=2;
                        test_snapshot[241:240]=1;test_snapshot[2:0]=7;
                    end
                    6:begin test_page=6;end
                endcase
            end
        end
    end
    always @(posedge audio_clk)begin
        #2;if(reference.audio_rst_n && gaudio!==raudio)$fatal(1,"FAIL: synthesized audio pin mismatch");
    end
    always @(posedge gp)if(gd)begin
        pixels=pixels+1;
        if(pixels==480*272*6)begin
            $display("PASS: synthesized menu LCD and full-width stage %0d clocks / %0d pixels; home/countdown/moving notes/header/repeated judgement/result, touch reset and silent PT8211/I2S match full RTL",clocks,pixels);
            $finish;
        end
    end
    initial begin #200000000;$fatal(1,"FAIL: gate stage watchdog");end
endmodule
