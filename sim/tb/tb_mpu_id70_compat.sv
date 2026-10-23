`timescale 1ns/1ps
module mpu_id70_case #(parameter [6:0] ADDRESS=7'h68)(input wire clk,rst_n,tick_ms,output reg finished=0);
    tri1 scl,sda;
    reg bad_id=0,bad_config=0,drdy=1,nak=0,hold_scl=0;
    assign scl=hold_scl ? 1'b0 : 1'bz;
    reg [111:0] packet={-16'sd32768,16'd32767,16'd8192,16'hcafe,16'd257,-16'sd2,-16'sd32760};
    wire ready,valid;wire [95:0] axes;
    wire [15:0] seqno;wire [7:0] faults;wire [2:0] fault;
    wire [31:0] writes,bursts;
    mpu6050_reader #(.CLK_HZ(1000000),.I2C_QUARTER(5),.ADDRESS(ADDRESS),.POWER_WAIT_MS(2),
        .RESET_WAIT_MS(2),.WAKE_WAIT_MS(2),.WAKE_WAIT_6500_MS(5),.POLL_MS(5),.STALE_MS(50),.RETRY_MS(20)) dut(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.scl(scl),.sda(sda),.ready(ready),.sample_valid(valid),
        .ax(axes[95:80]),.ay(axes[79:64]),.az(axes[63:48]),.gx(axes[47:32]),.gy(axes[31:16]),.gz(axes[15:0]),
        .sample_sequence(seqno),.fault_count(faults),.fault_code(fault));
    mpu6050_test_slave #(.WHO_AM_I(8'h70),.ADDRESS(ADDRESS),.BAD_CONFIG_REGISTER(8'h1d),.BAD_CONFIG_VALUE(8'h04)) slave(
        .scl(scl),.sda(sda),.rst_n(rst_n),.nak(nak),.bad_id(bad_id),.bad_config(bad_config),
        .data_ready(drdy),.packet(packet),.writes(writes),.bursts(bursts));
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL ID70 addr%h: %s",ADDRESS,why);endtask
    reg [95:0] held;
    always @(posedge clk)if(valid)check(axes=={packet[111:64],packet[47:0]},"atomic signed burst skips temperature");
    initial begin
        wait(rst_n);wait(ready);
        check(writes==12 && slave.registers[8'h1d]==3 && slave.registers[8'h1c]==8 && slave.registers[8'h19]==9,"reset plus all11 configs,4g,100Hz and independent accel filter");
        wait(valid);@(negedge clk);check(seqno==1,"first fresh packet sequence");
        wait(!valid);@(negedge clk);
        packet={16'd4096,-16'sd4096,16'd0,16'd0,-16'sd32768,16'd32767,16'd8192};
        wait(valid);@(negedge clk);check(seqno==2,"dynamic data update");
        drdy=0;held=axes;wait(!ready);check(fault==4 && axes==held && seqno==2,"stale data retained and not republished");
        drdy=1;bad_id=1;wait(fault==2);check(!ready,"unknown ID71 rejected");
        bad_id=0;bad_config=1;wait(fault==3);check(!ready && dut.bus_register==16'h1d,"6500 config2 readback mismatch blocks ready");
        bad_config=0;wait(ready);wait(valid);@(negedge clk);
        nak=1;wait(!ready);check(fault==1,"NAK fault");
        nak=0;wait(ready);wait(valid);@(negedge clk);
        wait(dut.state==15);held=axes;@(negedge scl);hold_scl=1;wait(!ready);
        check(fault==1 && axes==held && !dut.bus.scl_low && !dut.bus.sda_low,"partial burst discarded and clock timeout releases pins");
        hold_scl=0;wait(ready);wait(valid);@(negedge clk);
        check(seqno>=5 && faults>=5,"recovery resumes publication");finished=1;
    end
endmodule

module tb_mpu_id70_compat;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_ms=0;integer divider=0;
    always @(negedge clk)begin tick_ms=divider==999;divider=tick_ms ? 0 : divider+1;end
    wire done68,done69;
    mpu_id70_case a68(.clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.finished(done68));
    mpu_id70_case #(.ADDRESS(7'h69)) a69(.clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.finished(done69));
    tri1 nscl,nsda,oscl,osda;
    wire nr,nv,orr,ov;wire [95:0] na,oa;wire [15:0] nq,oq;wire [7:0] nf,of;wire [2:0] nc,oc;
    wire [31:0] nw,nb,ow,ob;
    `define PORTS(SC,SD,R,V,A,Q,F,C) .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.scl(SC),.sda(SD),.ready(R),.sample_valid(V),.ax(A[95:80]),.ay(A[79:64]),.az(A[63:48]),.gx(A[47:32]),.gy(A[31:16]),.gz(A[15:0]),.sample_sequence(Q),.fault_count(F),.fault_code(C)
    mpu6050_reader #(.CLK_HZ(1000000),.I2C_QUARTER(5),.POWER_WAIT_MS(2),.RESET_WAIT_MS(2),.WAKE_WAIT_MS(2)) current68(`PORTS(nscl,nsda,nr,nv,na,nq,nf,nc));
    accepted_mpu6050_reader #(.CLK_HZ(1000000),.I2C_QUARTER(5),.POWER_WAIT_MS(2),.RESET_WAIT_MS(2),.WAKE_WAIT_MS(2)) frozen68(`PORTS(oscl,osda,orr,ov,oa,oq,of,oc));
    `undef PORTS
    `define MODEL(SC,SD,W,B) .scl(SC),.sda(SD),.rst_n(rst_n),.nak(1'b0),.bad_id(1'b0),.bad_config(1'b0),.data_ready(1'b1),.packet({16'd0,16'd0,16'd8192,16'd0,16'd0,16'd0,16'd0}),.writes(W),.bursts(B)
    mpu6050_test_slave ns(`MODEL(nscl,nsda,nw,nb));
    mpu6050_test_slave os(`MODEL(oscl,osda,ow,ob));
    `undef MODEL
    integer cycles=0;
    always @(negedge clk)if(rst_n)begin
        cycles=cycles+1;
        if({nr,nv,na,nq,nf,nc,nscl,nsda}!=={orr,ov,oa,oq,of,oc,oscl,osda})$fatal(1,"FAIL: ID68 differs from independent frozen reader");
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;wait(done68 && done69);
        if(nq==0 || nw!=11 || ns.registers[8'h1d]!=0)$fatal(1,"FAIL: original 6050 path/configs");
        $display("PASS: production ID70 both addresses/config2/signed dynamic data/unknownID/config mismatch/NAK/stale/partial burst/recovery; frozen ID68 cycle equality %0d clocks",cycles);$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL: ID70 compatibility watchdog");end
endmodule
