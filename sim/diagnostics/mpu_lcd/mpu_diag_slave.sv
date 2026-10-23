`timescale 1ns/1ps
// Pin-level model, independently programmable address, ID and NACK stage.
module mpu_diag_slave(input wire scl,rst_n,present,address_high,bad_config,data_ready,
 input wire [7:0] who,input wire [2:0] nak_stage,
 input wire [111:0] packet,inout wire sda,output reg [31:0] writes=0,bursts=0);
    reg low=0;assign sda=low ? 1'b0 : 1'bz;
    reg [7:0] registers[0:127];
    reg [7:0] pointer=0,received=0,transmitted=0;
    reg [111:0] held_packet;
    integer state=0,next_state=0,bits=0,index=0,i;
    initial for(i=0;i<128;i=i+1)registers[i]=0;
    function [7:0] memory(input [7:0] address);
        if(address==8'h75)memory=who;
        else if(address==8'h3a)memory={7'd0,data_ready};
        else if(address>=8'h3b && address<=8'h48)memory=held_packet[111-(address-8'h3b)*8-:8];
        else if(address==8'h1c && bad_config)memory=8'h10;
        else memory=registers[address[6:0]];
    endfunction
    always @(negedge sda)if(scl===1 && rst_n)begin state=1;bits=0;received=0;index=0;end
    always @(posedge sda)if(scl===1)begin state=0;low=0;end
    always @(negedge rst_n)begin state=0;low=0;end
    always @(posedge scl)case(state)
        1:begin
            received={received[6:0],sda};bits=bits+1;
            if(bits==8)begin
                next_state=1;
                if(index==0)begin
                    if(received[7:1]!=(address_high ? 7'h69 : 7'h68) || !present ||
                       (!received[0] && nak_stage==1) || (received[0] && nak_stage==4))next_state=0;
                    else if(received[0])begin
                        next_state=4;
                        if(pointer==8'h3b)begin held_packet=packet;bursts=bursts+1;end
                    end
                end else if(index==1)begin
                    if(nak_stage==2)next_state=0;else pointer=received;
                end else if(nak_stage==3)next_state=0;
                else begin registers[pointer[6:0]]=received;pointer=pointer+1;writes=writes+1;end
                state=2;index=index+1;
            end
        end
        2:state=3;
        4:begin if(bits==0)state=5;else bits=bits-1;end
        5:begin next_state=sda===0 ? 4 : 0;state=6;pointer=pointer+1;end
    endcase
    always @(negedge scl)case(state)
        2:low=next_state!=0;
        3:begin
            low=0;state=next_state;
            if(state==4)begin bits=7;transmitted=memory(pointer);low=~transmitted[7];end
            else begin bits=0;received=0;end
        end
        4:low=~transmitted[bits];
        5:low=0;
        6:begin
            state=next_state;low=0;
            if(state==4)begin bits=7;transmitted=memory(pointer);low=~transmitted[7];end
        end
    endcase
endmodule
