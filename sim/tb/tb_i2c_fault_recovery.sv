`timescale 1ns/1ps
module tb_i2c_fault_recovery;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,hold_sda=0,hold_scl=0;
    reg [4:0] length=1;
    tri1 sda,scl;assign sda=hold_sda ? 1'b0 : 1'bz;assign scl=hold_scl ? 1'b0 : 1'bz;
    wire busy,done,error;wire [127:0] data;
    i2c_register_master #(.QUARTER_CYCLES(5),.TIMEOUT_CYCLES(3000)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.read_request(1'b1),.device_address(7'h5d),
        .register_address(16'h8140),.read_length(length),.write_data(8'd0),.scl(scl),.sda(sda),
        .busy(busy),.done(done),.error(error),.read_data(data));
    integer recover_edges=0,cycles=0;
    always @(posedge scl)if(rst_n && dut.state==8)begin
        recover_edges=recover_edges+1;
        if(recover_edges==9)hold_sda=0;
    end
    task launch;
        @(negedge clk);start=1;@(negedge clk);start=0;
    endtask
    task completed;
        cycles=0;while(!done)begin @(negedge clk);cycles=cycles+1;end
        if(!error || busy || cycles>3001)$fatal(1,"FAIL: bounded fault completion");
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        length=0;launch();completed();if(sda!==1 || scl!==1)$fatal(1,"FAIL: invalid request drives bus");
        length=17;launch();completed();
        length=1;hold_sda=1;repeat(5)@(negedge clk);launch();completed();
        if(recover_edges!=9 || sda!==1 || scl!==1)$fatal(1,"FAIL: nine recovery pulses and STOP");
        hold_scl=1;repeat(5)@(negedge clk);launch();completed();
        if(dut.scl_low || dut.sda_low)$fatal(1,"FAIL: timeout must release both outputs");
        hold_scl=0;repeat(5)@(negedge clk);launch();completed(); // No slave: NAK + STOP.
        if(sda!==1 || scl!==1)$fatal(1,"FAIL: NAK recovery idle");
        launch();repeat(10)@(negedge clk);rst_n=0;repeat(5)@(negedge clk);
        if(sda!==1 || scl!==1 || busy)$fatal(1,"FAIL: reset in transaction releases bus");
        $display("PASS: invalid lengths, nine-clock SDA recovery, stuck-SCL timeout, NAK/STOP and mid-transfer reset");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL: I2C fault watchdog");end
endmodule
