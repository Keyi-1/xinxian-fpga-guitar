// Read existing GT911 configuration. Never upload a replacement config table.
// Polling works regardless of the panel's interrupt polarity.
module gt911_touch #(
    parameter integer CLK_HZ=50000000,
    parameter integer I2C_QUARTER=125,
    parameter integer RESET_MS=20,
    parameter integer SELECT_MS=2,
    parameter integer RELEASE_MS=6,
    parameter integer SYNC_MS=50,
    parameter integer BOOT_MS=50,
    parameter integer POLL_MS=5
)(input wire clk,rst_n,inout wire ctp_scl,ctp_sda,ctp_int,
  output wire ctp_rst_n,output reg ready,frame_valid,
  output reg [3:0] touch_count,output reg [7:0] touch_id,
  output reg [15:0] raw_x,raw_y,max_x,max_y,
  output reg [31:0] product_id,output reg [15:0] firmware,
  output reg [7:0] fault_count,output wire [6:0] selected_address);
    localparam RESET=0,SELECT=1,RELEASE=2,SYNC=3,BOOT=4,ID_START=5,ID_WAIT=6,
               POLL=7,FRAME_START=8,FRAME_WAIT=9,CLEAR_START=10,CLEAR_WAIT=11,RETRY=12;
    reg [3:0] state;
    reg [31:0] timer;
    reg address_high;
    reg bus_start,bus_read;
    reg [15:0] bus_register;
    reg [4:0] bus_length;
    wire busy,done,error;
    wire [127:0] data;
    reg [71:0] held_frame;
    assign selected_address=address_high ? 7'h14 : 7'h5d;
    assign ctp_rst_n=state>=RELEASE;
    // INT is driven only while the controller is held in reset/address select.
    assign ctp_int=state==RESET || state==SELECT || state==RELEASE ? address_high :
                   state==SYNC ? 1'b0 : 1'bz;
    i2c_register_master #(.QUARTER_CYCLES(I2C_QUARTER),.TIMEOUT_CYCLES(CLK_HZ/100)) u_bus(
        .clk(clk),.rst_n(rst_n),.start(bus_start),.read_request(bus_read),
        .device_address(selected_address),.register_address(bus_register),
        .read_length(bus_length),.write_data(8'd0),.scl(ctp_scl),.sda(ctp_sda),
        .busy(busy),.done(done),.error(error),.read_data(data));
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=RESET;timer<=0;address_high<=0;ready<=0;frame_valid<=0;
            touch_count<=0;touch_id<=0;raw_x<=0;raw_y<=0;max_x<=0;max_y<=0;
            product_id<=0;firmware<=0;fault_count<=0;held_frame<=0;
            bus_start<=0;bus_read<=1;bus_register<=0;bus_length<=1;
        end else begin
            bus_start<=0;frame_valid<=0;
            case(state)
                RESET,SELECT,RELEASE,SYNC,BOOT:begin
                    timer<=timer+1'b1;
                    if((state==RESET && timer>=CLK_HZ/1000*RESET_MS-1) ||
                       (state==SELECT && timer>=CLK_HZ/1000*SELECT_MS-1) ||
                       (state==RELEASE && timer>=CLK_HZ/1000*RELEASE_MS-1) ||
                       (state==SYNC && timer>=CLK_HZ/1000*SYNC_MS-1) ||
                       (state==BOOT && timer>=CLK_HZ/1000*BOOT_MS-1))begin
                        timer<=0;state<=state+1'b1;
                    end
                end
                ID_START:if(!busy)begin
                    bus_register<=16'h8140;bus_length<=10;bus_read<=1;bus_start<=1;state<=ID_WAIT;
                end
                ID_WAIT:if(done)begin
                    if(error || data[23:0]!=24'h313139 || data[63:48]==0 || data[79:64]==0 ||
                       data[63:48]>4096 || data[79:64]>4096)begin
                        ready<=0;fault_count<=fault_count==255 ? 8'd255 : fault_count+1'b1;
                        state<=RETRY;timer<=0;
                    end else begin
                        product_id<=data[31:0];firmware<=data[47:32];max_x<=data[63:48];max_y<=data[79:64];
                        ready<=1;timer<=0;state<=POLL;
                    end
                end
                POLL:begin
                    timer<=timer+1'b1;
                    if(timer>=CLK_HZ/1000*POLL_MS-1)begin state<=FRAME_START;timer<=0;end
                end
                FRAME_START:if(!busy)begin
                    bus_register<=16'h814e;bus_length<=9;bus_read<=1;bus_start<=1;state<=FRAME_WAIT;
                end
                FRAME_WAIT:if(done)begin
                    if(error)begin ready<=0;state<=RETRY;timer<=0;frame_valid<=1;touch_count<=15;
                        fault_count<=fault_count==255 ? 8'd255 : fault_count+1'b1;end
                    else if(data[7])begin held_frame<=data[71:0];state<=CLEAR_START;end
                    else state<=POLL;
                end
                CLEAR_START:if(!busy)begin
                    bus_register<=16'h814e;bus_read<=0;bus_start<=1;state<=CLEAR_WAIT;
                end
                CLEAR_WAIT:if(done)begin
                    if(error)begin ready<=0;state<=RETRY;timer<=0;frame_valid<=1;touch_count<=15;
                        fault_count<=fault_count==255 ? 8'd255 : fault_count+1'b1;end
                    else begin
                        frame_valid<=1;
                        touch_count<=held_frame[6] || held_frame[4] || held_frame[3:0]>5 ? 4'd15 : held_frame[3:0];
                        touch_id<=held_frame[15:8];raw_x<=held_frame[31:16];raw_y<=held_frame[47:32];state<=POLL;
                    end
                end
                RETRY:begin
                    timer<=timer+1'b1;
                    if(timer>=CLK_HZ-1)begin address_high<=~address_high;timer<=0;state<=RESET;end
                end
                default:state<=RESET;
            endcase
        end
    end
endmodule
