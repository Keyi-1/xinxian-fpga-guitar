`timescale 1ns/1ps
module tb_mpu_lcd_diag;
    reg clk=0;always #10 clk=~clk; // Real 50 MHz and production 100 kHz I2C.
    reg rst_n=0,tick_ms=0;
    integer divider=0;
    always @(negedge clk)begin tick_ms=divider==49999;divider=tick_ms ? 0 : divider+1;end
    tri1 scl,sda;
    reg present=0,address_high=0,bad_config=0,data_ready=1,hold_scl=0,hold_sda=0;
    reg [7:0] who=8'h68;
    reg [2:0] nak_stage=0;
    reg [111:0] packet={-16'sd32768,16'd32767,16'd8192,16'hcafe,16'd257,-16'sd4321,16'd0};
    assign scl=hold_scl ? 1'b0 : 1'bz;assign sda=hold_sda ? 1'b0 : 1'bz;
    wire a68,a69,v68,v69,iscl,isda,valid;
    wire [7:0] id68,id69,addr,chip_id,regno,expected,actual;
    wire [3:0] e68,e69,status,error;
    wire [4:0] step,failed_step;
    wire [31:0] count,faults,writes,bursts;
    wire [15:0] age;
    wire [95:0] axes;
    mpu_lcd_diag_reader #(.POWER_MS(1),.RESET_MS(2),.WAKE_MS(1),.RETRY_MS(3),.POLL_MS(1),.STALE_MS(15)) dut(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.scl(scl),.sda(sda),.ack68(a68),.ack69(a69),
        .id68_valid(v68),.id69_valid(v69),.id68(id68),.id69(id69),.selected_address(addr),.selected_id(chip_id),
        .error68(e68),.error69(e69),.status(status),.last_error(error),.step(step),.last_fault_step(failed_step),
        .last_register(regno),.expected_value(expected),.actual_value(actual),.sample_count(count),
        .fault_count(faults),.sample_age(age),.axes(axes),.idle_scl(iscl),.idle_sda(isda),.sample_valid(valid));
    mpu_diag_slave slave(.scl(scl),.sda(sda),.rst_n(rst_n),.present(present),.address_high(address_high),
        .bad_config(bad_config),.data_ready(data_ready),.who(who),.nak_stage(nak_stage),.packet(packet),.writes(writes),.bursts(bursts));
    task check(input bit ok,input string reason);if(!ok)$fatal(1,"FAIL: %s step%0d error%0d",reason,step,error);endtask
    reg [95:0] held;
    integer checks=0;
    always @(posedge clk)if(valid)begin
        check(axes=={packet[111:64],packet[47:0]},"atomic signed burst skips temperature");checks=checks+1;
    end
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        wait(status==1);check(!a68 && !a69 && error==1,"absent device = address NACK");
        check(writes==0 && iscl && isda,"no writes and idle high when absent");
        present=1;who=8'h71;wait(status==2);check(a68 && v68 && id68==8'h71 && error==10,"actual unexpected WHO retained");
        check(writes==0,"unknown chip never initialized");
        who=8'h68;wait(status==7);check(addr==8'h68 && chip_id==8'h68 && a68 && !a69 && count>=10,"68 PASS after ten packets");
        check(slave.registers[8'h1d]==0,"6050 never writes 6500 accel config2");
        data_ready=0;wait(status==5);check(error==8,"stale samples distinctly reported");held=axes;
        nak_stage=2;wait(e68==2);check(a68 && !v68,"register NACK distinct from address NACK");
        nak_stage=4;wait(e68==4);check(a68 && !v68,"read-address NACK distinct");
        nak_stage=3;data_ready=1;wait(status==4);check(error==3 && regno==8'h6b,"write-data NACK on reset");
        nak_stage=0;bad_config=1;wait(error==7);check(regno==8'h1c && expected==8 && actual==8'h10 && failed_step==12,"configuration mismatch retained");
        bad_config=0;address_high=1;wait(status==7 && addr==8'h69);check(a69 && v69 && id69==8'h68 && !a68,"69 with WHO68 accepted");
        hold_scl=1;wait(error==5);check(!dut.bus.scl_low && !dut.bus.sda_low,"SCL timeout releases both drivers");
        hold_scl=0;hold_sda=1;wait(e68==6 && e69==6);check(!isda,"SDA stuck reflected at idle snapshot");
        hold_sda=0;wait(status==7);check(count>20,"recovery resumes samples");
        // Retry with ID70 at each physical address, without changing AD0 in firmware.
        data_ready=0;wait(status==5);who=8'h70;address_high=0;data_ready=1;
        wait(status==7 && chip_id==8'h70 && addr==8'h68);
        check(slave.registers[8'h1d]==3 && slave.registers[8'h1c]==8 && slave.registers[8'h19]==9,"6500 full profile including accel DLPF");
        data_ready=0;wait(status==5);address_high=1;data_ready=1;
        wait(status==7 && chip_id==8'h70 && addr==8'h69);
        check(a69 && !a68 && v69 && id69==8'h70,"ID70 and physical address69 distinct");
        $display("PASS: LCD diagnostic reader absent/6050/6500/both addresses/unknown ID/NACK/config/stale/stuck/recovery, %0d full packets",checks);
        $finish;
    end
    initial begin #500000000;$fatal(1,"FAIL: watchdog step%0d status%0d err%0d e68%0d",step,status,error,e68);end
endmodule
