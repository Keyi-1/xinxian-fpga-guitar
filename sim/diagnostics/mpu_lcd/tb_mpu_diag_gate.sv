`timescale 1ns/1ps
// Unmodified actual synthesis netlist versus RTL, with real power/reset delays.
module tb_mpu_diag_gate;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #10 clk=~clk;
    tri1 scl,sda,rscl,rsda;
    wire pclk,hs,vs,de,backlight,pa,rpclk,rhs,rvs,rde,rbacklight,rpa;
    wire [5:0] r,g,b,rr,rg,rb;
    wire [31:0] writes,bursts,rwrites,rbursts;
    reg [111:0] packet={-16'sd2048,16'd1024,16'd8192,16'hcafe,16'd257,-16'sd4321,16'd0};
    neo_mpu6050_lcd_diagnostic_top dut(.sys_clk_50m(clk),.imu_scl(scl),.imu_sda(sda),
        .lcd_pclk(pclk),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_de(de),.lcd_backlight(backlight),
        .lcd_r(r),.lcd_g(g),.lcd_b(b),.pa_en_n(pa));
    ref_neo_mpu6050_lcd_diagnostic_top reference(.sys_clk_50m(clk),.imu_scl(rscl),.imu_sda(rsda),
        .lcd_pclk(rpclk),.lcd_hsync(rhs),.lcd_vsync(rvs),.lcd_de(rde),.lcd_backlight(rbacklight),
        .lcd_r(rr),.lcd_g(rg),.lcd_b(rb),.pa_en_n(rpa));
    mpu_diag_slave slave(.scl(scl),.sda(sda),.rst_n(reference.rst_n),.present(1'b1),.address_high(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.who(8'h70),.nak_stage(3'd0),.packet(packet),.writes(writes),.bursts(bursts));
    mpu_diag_slave refslave(.scl(rscl),.sda(rsda),.rst_n(reference.rst_n),.present(1'b1),.address_high(1'b0),
        .bad_config(1'b0),.data_ready(1'b1),.who(8'h70),.nak_stage(3'd0),.packet(packet),.writes(rwrites),.bursts(rbursts));
    integer compared=0,frames=0,pass_pixels=0;
    reg comparing=0;
    always @(negedge clk)if(reference.rst_n)begin
        if({scl,sda}!=={rscl,rsda})$fatal(1,"FAIL: synthesized I2C pins differ at %0t",$time);
    end
    always @(posedge pclk)begin
        #1;
        if(reference.rst_n)begin
            if({pclk,hs,vs,de,backlight,pa,r,g,b}!=={rpclk,rhs,rvs,rde,rbacklight,rpa,rr,rg,rb})
                $fatal(1,"FAIL: synthesized LCD pins differ at %0t",$time);
            if(de)begin compared=compared+1;if(comparing)pass_pixels=pass_pixels+1;end
        end
    end
    initial begin
        wait(reference.status==7);
        @(posedge reference.frame);comparing=1;
        @(posedge reference.frame);frames=frames+1;
        packet={16'd4096,-16'sd4096,16'd0,16'd0,-16'sd32768,16'd32767,16'd8192};
        wait(reference.axes=={packet[111:64],packet[47:0]});
        @(posedge reference.frame);@(posedge reference.frame);frames=frames+1;
        if(writes!=12 || writes!=rwrites || bursts!=rbursts || bursts<10 || pass_pixels<261120 ||
           reference.chip_id!=8'h70 || slave.registers[8'h1d]!=3)
            $fatal(1,"FAIL: complete init/sample/frame coverage");
        $display("PASS: actual VG equals RTL, MPU6500 ID70/config2, real startup/reset waits, %0d active pixels, %0d packets, dynamic signed axes",compared,bursts);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: netlist watchdog");end
endmodule
