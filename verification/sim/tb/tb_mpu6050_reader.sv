`timescale 1ns/1ps
module tb_mpu6050_reader;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_ms=0;
    integer divider=0;
    always @(negedge clk)begin tick_ms=divider==999;divider=tick_ms ? 0 : divider+1;end
    tri1 scl,sda;
    reg nak=0,bad_id=0,bad_config=0,data_ready=1,hold_scl=0;
    reg [111:0] packet={16'd1234,-16'sd4321,16'd8192,16'hcafe,16'd257,-16'sd2,-16'sd32760};
    wire ready,valid;wire signed [15:0] ax,ay,az,gx,gy,gz;
    wire [15:0] sample_id;wire [7:0] faults;wire [2:0] fault;
    wire [31:0] writes,bursts;
    assign scl=hold_scl ? 1'b0 : 1'bz;
    mpu6050_reader #(.CLK_HZ(1000000),.I2C_QUARTER(5),.POWER_WAIT_MS(2),
        .RESET_WAIT_MS(2),.WAKE_WAIT_MS(2),.POLL_MS(5),.STALE_MS(50),.RETRY_MS(20)) dut(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.scl(scl),.sda(sda),.ready(ready),.sample_valid(valid),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.sample_sequence(sample_id),.fault_count(faults),.fault_code(fault));
    mpu6050_test_slave slave(.scl(scl),.sda(sda),.rst_n(rst_n),.nak(nak),.bad_id(bad_id),
        .bad_config(bad_config),.data_ready(data_ready),.packet(packet),.writes(writes),.bursts(bursts));
    integer published=0;reg [95:0] last_packet;
    always @(posedge clk)if(valid)begin
        published=published+1;
        if({ax,ay,az,gx,gy,gz}!=={packet[111:64],packet[47:0]})$fatal(1,"FAIL: signed big-endian full packet");
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        wait(ready);check(writes==11,"reset plus all10 config writes and readbacks");
        wait(valid);@(negedge clk);check(sample_id==1 && bursts==1,"one atomic burst/sequence");
        check(ax==1234 && ay==-4321 && az==8192 && gx==257 && gy==-2 && gz==-32760,"signed decoding/temp skipped");
        data_ready=0;last_packet={ax,ay,az,gx,gy,gz};
        repeat(25000)@(negedge clk);check(sample_id==1 && {ax,ay,az,gx,gy,gz}==last_packet,"not-ready does not republish");
        wait(!ready);check(fault==4,"stale status is a fault");
        data_ready=1;wait(ready);wait(valid);@(negedge clk);
        nak=1;wait(!ready);check(fault==1,"NAK bounded fault");
        bad_id=1;nak=0;wait(fault==2);check(!ready,"wrong ID cannot ready");
        bad_id=0;bad_config=1;wait(fault==3);check(!ready,"ACK without correct readback cannot ready");
        bad_config=0;wait(ready);wait(valid);@(negedge clk);
        wait(dut.state==15);last_packet={ax,ay,az,gx,gy,gz};
        @(negedge scl);hold_scl=1;wait(!ready);
        check(fault==1 && {ax,ay,az,gx,gy,gz}==last_packet,"interrupted burst does not publish partial data");
        check(!dut.bus.scl_low && !dut.bus.sda_low,"stuck SCL timeout releases outputs");
        hold_scl=0;wait(ready);wait(valid);@(negedge clk);
        rst_n=0;repeat(5)@(negedge clk);check(!ready && !valid && scl===1 && sda===1,"reset releases independent bus");
        $display("PASS: MPU one-byte pointer/reset/10 readback configs/14-byte signed burst/no-DRDY/stale/NAK/ID/readback/clock-timeout/recovery, %0d packets",published);$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: MPU reader watchdog state%0d fault%0d",dut.state,fault);end
endmodule
