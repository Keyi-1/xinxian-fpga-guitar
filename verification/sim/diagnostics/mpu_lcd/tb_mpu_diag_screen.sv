`timescale 1ns/1ps
module tb_mpu_diag_screen;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame=0;
    reg [8:0] x=0,y=0;
    reg [95:0] axes={-16'sd32768,16'd32767,16'd8192,-16'sd4321,16'd257,16'd0};
    wire [17:0] rgb;
    mpu_lcd_diag_screen dut(.clk(clk),.rst_n(rst_n),.frame_start(frame),.x(x),.y(y),
        .ack68(1'b1),.ack69(1'b0),.id68_valid(1'b1),.id69_valid(1'b0),.id68(8'h68),.id69(8'd0),
        .address(8'h68),.chip_id(8'h70),.error68(4'd0),.error69(4'd1),.status(4'd7),.last_error(4'd0),
        .step(5'd14),.regno(8'h3b),.expected(8'd1),.actual(8'd1),.count(32'h1234abcd),.faults(32'd0),
        .age(16'd3),.axes(axes),.idle_scl(1'b1),.idle_sda(1'b1),.rgb(rgb));
    integer out,xx,yy,pixels=0;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;frame=1;@(negedge clk);frame=0;
        repeat(110)@(negedge clk);
        if(dut.bcd_axes!=={20'h32768,20'h32767,20'h08192,20'h04321,20'h00257,20'h00000} || dut.signs!=6'b100100)
            $fatal(1,"FAIL: signed BCD boundary conversion %h %b",dut.bcd_axes,dut.signs);
        axes=0;
        repeat(200)@(negedge clk);
        if(dut.raw_axes==0 || dut.bcd_axes[119:100]!=20'h32768)$fatal(1,"FAIL: snapshot tearing");
        out=$fopen("lcd_diag_pass.ppm","w");$fwrite(out,"P3\n480 272\n255\n");
        for(yy=0;yy<272;yy=yy+1)begin
            for(xx=0;xx<480;xx=xx+1)begin
                @(negedge clk);x=xx;y=yy;
                repeat(5)@(negedge clk); // Same six system clocks per pixel as LCD scan.
                if(^rgb===1'bx)$fatal(1,"FAIL: unknown pixel");
                $fwrite(out,"%0d %0d %0d\n",rgb[17:12]*4,rgb[11:6]*4,rgb[5:0]*4);pixels=pixels+1;
            end
        end
        $fclose(out);
        $display("PASS: signed min/max BCD, frame snapshot, six-clock renderer and %0d pixels",pixels);$finish;
    end
    initial begin #30000000;$fatal(1,"FAIL: screen watchdog");end
endmodule
