`timescale 1ns/1ps
module tb_gt911_touch;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    tri1 scl,sda,int_pin;
    wire reset_n,ready,valid;wire [3:0] count;wire [7:0] id,faults;
    wire [15:0] x,y,mx,my,firmware;wire [31:0] product;wire [6:0] selected;
    reg slave_low=0,stretch_low=0,nak=0;
    assign sda=slave_low ? 1'b0 : 1'bz;assign scl=stretch_low ? 1'b0 : 1'bz;
    gt911_touch #(.CLK_HZ(1000000),.I2C_QUARTER(5)) dut(.clk(clk),.rst_n(rst_n),
        .ctp_scl(scl),.ctp_sda(sda),.ctp_int(int_pin),.ctp_rst_n(reset_n),.ready(ready),.frame_valid(valid),
        .touch_count(count),.touch_id(id),.raw_x(x),.raw_y(y),.max_x(mx),.max_y(my),
        .product_id(product),.firmware(firmware),.fault_count(faults),.selected_address(selected));
    integer state=0,bit_count=0,write_index=0,next_state=0;
    reg [7:0] receive_byte=0,transmit_byte=0;
    reg [15:0] pointer=0;
    reg [7:0] status=0;
    integer clears=0,starts=0;
    function [7:0] memory(input [15:0] a);
        case(a)
            16'h8140:memory="9";16'h8141,16'h8142:memory="1";16'h8143:memory=0;
            16'h8144:memory=8'h34;16'h8145:memory=8'h12;
            16'h8146:memory=8'he0;16'h8147:memory=1;16'h8148:memory=8'h10;16'h8149:memory=1;
            16'h814e:memory=status;16'h814f:memory=7;
            16'h8150:memory=8'h4d;16'h8151:memory=1;16'h8152:memory=123;
            default:memory=0;
        endcase
    endfunction
    always @(negedge sda)if(scl===1 && reset_n)begin
        state=1;bit_count=0;receive_byte=0;write_index=0;starts=starts+1;
    end
    always @(posedge sda)if(scl===1)begin state=0;slave_low=0;end
    always @(posedge scl)case(state)
        1:begin
            receive_byte={receive_byte[6:0],sda};bit_count=bit_count+1;
            if(bit_count==8)begin
                next_state=1;
                if(write_index==0)begin
                    if(receive_byte[7:1]!=selected || nak)next_state=0;
                    else if(receive_byte[0])next_state=4;
                end else if(write_index==1)pointer[15:8]=receive_byte;
                else if(write_index==2)pointer[7:0]=receive_byte;
                else begin if(pointer==16'h814e && receive_byte==0)begin status=0;clears=clears+1;end pointer=pointer+1;end
                state=2;write_index=write_index+1;
            end
        end
        2:state=3;
        4:begin if(bit_count==0)state=5;else bit_count=bit_count-1;end
        5:begin next_state=sda===0 ? 4 : 0;state=6;pointer=pointer+1;end
    endcase
    always @(negedge scl)case(state)
        2:slave_low=next_state!=0;
        3:begin slave_low=0;state=next_state;
            if(state==4)begin bit_count=7;transmit_byte=memory(pointer);slave_low=~transmit_byte[7];end
            else begin bit_count=0;receive_byte=0;end
        end
        4:slave_low=~transmit_byte[bit_count];
        5:slave_low=0;
        6:begin state=next_state;slave_low=0;
            if(state==4)begin bit_count=7;transmit_byte=memory(pointer);slave_low=~transmit_byte[7];end
        end
    endcase
    task check(input bit pass,input string why);if(!pass)$fatal(1,"FAIL: %s",why);endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        wait(ready);check(product[23:0]==24'h313139 && firmware==16'h1234 && mx==480 && my==272,"ID and existing coordinate range");
        status=8'h81;@(posedge valid);#1;check(count==1 && x==333 && y==123 && id==7 && clears==1,"touch frame and clear-ready write");
        status=8'h80;@(posedge valid);#1;check(count==0 && clears==2,"finger up frame");
        status=8'h82;@(posedge valid);#1;check(count==2,"multiple fingers retained for gesture cancellation");
        // Clock stretching stalls phase advancement, without changing the transaction.
        fork begin @(negedge scl);stretch_low=1;repeat(100)@(negedge clk);stretch_low=0;end
             begin status=8'h81;@(posedge valid);#1;check(count==1 && x==333,"clock-stretched frame");end join
        nak=1;wait(!ready);check(faults!=0,"NAK is bounded and reported");nak=0;
        wait(ready);check(selected==7'h14,"reset/address fallback after failed poll");
        $display("PASS: GT911 reset/address, repeated START, ID/resolution, touches/UP/multitouch, clear-ready, stretch and NAK recovery");$finish;
    end
    initial begin #20000000;$fatal(1,"FAIL: GT911 watchdog state=%0d faults=%0d",dut.state,faults);end
endmodule
