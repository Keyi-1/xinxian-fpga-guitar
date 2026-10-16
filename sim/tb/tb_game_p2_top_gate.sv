`timescale 1ns/1ps
// Compare actual synthesized GPIO/LCD/audio outputs to the complete RTL top.
// Display-only snapshots exercise the real full-width synthesized renderer.
// LCD coordinates are never forced: all pixels use the physical scan cadence.
module tb_game_p2_top_gate;
    GSR GSR(.GSRI(1'b1));
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
    reg [399:0] test_visual=0;
    reg [159:0] test_targets=0;
    reg [2:0] test_selected=3;
    integer mutation=0;
    localparam FRAME_COUNT=10;
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
                    2:begin test_page=2;end
                    3:begin test_page=3;end
                    4:begin test_page=4;test_snapshot[95:64]=-48000;
                        test_snapshot[229:228]=2;test_snapshot[230]=1;test_snapshot[237:235]=3;test_snapshot[255:250]=1;end
                    5:begin test_page=5;test_snapshot[95:64]=96000;test_snapshot[230]=0;
                        test_snapshot[237:235]=2;test_snapshot[255:250]=2;test_snapshot[0]=1;
                        test_snapshot[127:96]=12700;test_snapshot[143:128]=128;
                        test_snapshot[159:144]=300;test_snapshot[175:160]=256;
                        test_snapshot[210:208]=1;test_snapshot[221:220]=1;end
                    6:begin test_snapshot[95:64]=6144000;test_snapshot[237:235]=1;
                        test_snapshot[249:238]=126;test_snapshot[255:250]=3;test_snapshot[63:0]=0;
                        test_snapshot[127:96]=204800;test_snapshot[143:128]=2048;
                        test_snapshot[159:144]=65535;test_snapshot[175:160]=300;test_snapshot[191:176]=256;
                        test_snapshot[213:211]=2;test_snapshot[223:222]=1;end
                    7:begin test_page=6;end
                    8:begin test_page=1;
                        test_visual[335:332]=15;test_visual[367:352]=16'hffff;test_visual[399:368]=32'h01010101;
                        for(integer j=0;j<4;j=j+1)begin
                            test_visual[128+j*32+:32]=32'd19685267+j*32'd4123000;
                            test_visual[288+j*11+:11]=220+j*55;
                        end
                        for(integer j=0;j<32;j=j+1)test_targets[j*5+:5]=j;
                    end
                    9:begin test_targets=0;test_visual[335:332]=0;test_visual[367:352]=0;end
                    10:begin test_page=0;end
                endcase
            end

            if(reference.u_display.visual_update)mutation=7;
            else if(mutation!=0)begin
                mutation=mutation-1;
                if(mutation==0)test_targets=~test_targets;
            end

        end
    end
    always @(posedge audio_clk)begin
        #2;if(reference.audio_rst_n && gaudio!==raudio)$fatal(1,"FAIL: synthesized audio pin mismatch");
    end
    always @(posedge gp)if(gd)begin
        pixels=pixels+1;
        if(pixels==480*272*FRAME_COUNT)begin

            $display("PASS: synthesized P2 full top %0d clocks / %0d pixels; ten frames, menu/selected melody/countdown/wah/long-song ring head/16-bit results, dynamic spectrum and page switches; actual six-clock LCD scan, GPIO and silent PT8211/I2S match",clocks,pixels);
            $finish;
        end
    end
    initial begin #500000000;$fatal(1,"FAIL: gate stage watchdog");end
endmodule
