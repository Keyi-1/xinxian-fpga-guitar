// Single-master, open-drain I2C; 16-bit register pointer, 1..16 byte reads,
// or one byte writes. All state uses clk, including clock-stretch timeout.
module i2c_register_master #(
    parameter integer QUARTER_CYCLES=125,
    parameter integer TIMEOUT_CYCLES=500000
)(input wire clk,rst_n,start,read_request,
  input wire [6:0] device_address,input wire [15:0] register_address,
  input wire [4:0] read_length,input wire [7:0] write_data,
  inout wire scl,sda,output reg busy,done,error,
  output reg [127:0] read_data);
    localparam IDLE=0,START=1,TX=2,ACK=3,RESTART=4,RX=5,RACK=6,STOP=7,RECOVER=8;
    reg [3:0] state;
    reg [1:0] quarter;
    reg scl_low,sda_low;
    reg [1:0] scl_sync,sda_sync;
    reg [31:0] divider,watchdog;
    reg [6:0] address;
    reg [15:0] pointer;
    reg rd;
    reg [4:0] length;
    reg [3:0] rx_index;
    reg [2:0] kind,bit_index;
    reg [3:0] recovery_count;
    reg [7:0] tx_byte,rx_byte,data_byte;
    assign scl=scl_low ? 1'b0 : 1'bz;
    assign sda=sda_low ? 1'b0 : 1'bz;
    wire tick=divider==QUARTER_CYCLES-1;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;quarter<=0;scl_low<=0;sda_low<=0;
            scl_sync<=3;sda_sync<=3;divider<=0;watchdog<=0;
            busy<=0;done<=0;error<=0;read_data<=0;
            address<=0;pointer<=0;rd<=0;length<=0;rx_index<=0;
            kind<=0;bit_index<=7;recovery_count<=0;tx_byte<=0;rx_byte<=0;data_byte<=0;
        end else begin
            scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};done<=0;
            if(!busy)begin
                divider<=0;watchdog<=0;scl_low<=0;sda_low<=0;
                if(start)begin
                    address<=device_address;pointer<=register_address;rd<=read_request;
                    length<=read_length;data_byte<=write_data;rx_index<=0;read_data<=0;
                    quarter<=0;kind<=0;bit_index<=7;tx_byte<={device_address,1'b0};
                    recovery_count<=0;busy<=1;error<=0;
                    if(read_request && (read_length==0 || read_length>16))begin
                        busy<=0;done<=1;error<=1;
                    end else if(!sda_sync[1])begin state<=RECOVER;error<=1;end
                    else state<=START;
                end
            end else if(watchdog==TIMEOUT_CYCLES-1)begin
                // Release both lines even if another device holds SCL low.
                busy<=0;done<=1;error<=1;state<=IDLE;scl_low<=0;sda_low<=0;divider<=0;
            end else begin
                watchdog<=watchdog+1'b1;
                if(!scl_low && !scl_sync[1])divider<=0;
                else if(tick)begin
                    divider<=0;quarter<=quarter+1'b1;
                    case(state)
                        START:case(quarter)
                            0:begin scl_low<=0;sda_low<=0;end
                            1:sda_low<=1;
                            2:scl_low<=1;
                            3:begin state<=TX;quarter<=0;end
                        endcase
                        TX:case(quarter)
                            0:begin scl_low<=1;sda_low<=~tx_byte[bit_index];end
                            1:scl_low<=0;
                            2:;
                            3:begin scl_low<=1;
                                if(bit_index==0)begin state<=ACK;quarter<=0;end
                                else bit_index<=bit_index-1'b1;
                            end
                        endcase
                        ACK:case(quarter)
                            0:sda_low<=0;
                            1:scl_low<=0;
                            2:if(sda_sync[1])error<=1;
                            3:begin
                                scl_low<=1;quarter<=0;bit_index<=7;
                                if(error)state<=STOP;
                                else case(kind)
                                    0:begin kind<=1;tx_byte<=pointer[15:8];state<=TX;end
                                    1:begin kind<=2;tx_byte<=pointer[7:0];state<=TX;end
                                    2:if(rd)state<=RESTART;
                                      else begin kind<=3;tx_byte<=data_byte;state<=TX;end
                                    3:state<=STOP;
                                    default:begin state<=RX;rx_byte<=0;end
                                endcase
                            end
                        endcase
                        RESTART:case(quarter)
                            0:sda_low<=0;
                            1:scl_low<=0;
                            2:sda_low<=1;
                            3:begin scl_low<=1;kind<=4;tx_byte<={address,1'b1};
                                bit_index<=7;state<=TX;quarter<=0;end
                        endcase
                        RX:case(quarter)
                            0:begin scl_low<=1;sda_low<=0;end
                            1:scl_low<=0;
                            2:rx_byte[bit_index]<=sda_sync[1];
                            3:begin scl_low<=1;
                                if(bit_index==0)begin
                                    read_data[rx_index*8+:8]<=rx_byte;state<=RACK;quarter<=0;
                                end else bit_index<=bit_index-1'b1;
                            end
                        endcase
                        RACK:case(quarter)
                            0:sda_low<=({1'b0,rx_index}+1'b1)<length;
                            1:scl_low<=0;
                            2:;
                            3:begin scl_low<=1;sda_low<=0;quarter<=0;
                                if({1'b0,rx_index}+1'b1==length)state<=STOP;
                                else begin rx_index<=rx_index+1'b1;bit_index<=7;state<=RX;end
                            end
                        endcase
                        RECOVER:case(quarter)
                            0:begin scl_low<=1;sda_low<=0;end
                            1:;
                            2:scl_low<=0;
                            3:if(recovery_count==8)begin state<=STOP;quarter<=0;end
                              else recovery_count<=recovery_count+1'b1;
                        endcase
                        STOP:case(quarter)
                            0:begin scl_low<=1;sda_low<=1;end
                            1:scl_low<=0;
                            2:sda_low<=0;
                            3:begin busy<=0;done<=1;state<=IDLE;end
                        endcase
                        default:begin busy<=0;done<=1;error<=1;state<=IDLE;end
                    endcase
                end else divider<=divider+1'b1;
            end
        end
    end
endmodule
