// Independent MPU-6050/6500 bus. Identity selects an explicit register profile.
// Signed six-axis packets publish only after a successful 14-byte burst.
module mpu6050_reader #(
    parameter integer CLK_HZ=50000000,
    parameter integer I2C_QUARTER=125,
    parameter [6:0] ADDRESS=7'h68,
    parameter integer POWER_WAIT_MS=100,RESET_WAIT_MS=100,WAKE_WAIT_MS=30,
    parameter integer WAKE_WAIT_6500_MS=50,
    parameter integer POLL_MS=5,STALE_MS=100,RETRY_MS=1000
)(input wire clk,rst_n,tick_ms,inout wire scl,sda,
  output reg ready,sample_valid,
  output reg signed [15:0] ax,ay,az,gx,gy,gz,
  output reg [15:0] sample_sequence,
  output reg [7:0] fault_count,output reg [2:0] fault_code);
    localparam BOOT=0,RESET_START=1,RESET_DONE=2,RESET_WAIT=3,
        ID_START=4,ID_DONE=5,WRITE_START=6,WRITE_DONE=7,
        READBACK_START=8,READBACK_DONE=9,WAKE_WAIT=10,
        POLL_WAIT=11,STATUS_START=12,STATUS_DONE=13,
        DATA_START=14,DATA_DONE=15,RETRY=16;
    reg [4:0] state;
    reg [3:0] config_index;
    reg [15:0] timer,age_ms;
    reg mpu6500;
    reg bus_start,bus_read;
    reg [15:0] bus_register;
    reg [4:0] bus_length;
    reg [7:0] bus_write;
    wire busy,done,error;
    wire [127:0] data;
    function [7:0] config_register;
        input [3:0] index;
        case(index)
            0:config_register=8'h6b;1:config_register=8'h6c;
            2:config_register=8'h1a;3:config_register=8'h19;
            4:config_register=8'h1b;5:config_register=8'h1c;
            6:config_register=8'h23;7:config_register=8'h6a;
            8:config_register=8'h37;9:config_register=8'h38;
            default:config_register=8'h1d;
        endcase
    endfunction
    function [7:0] config_value;
        input [3:0] index;
        case(index)
            0,9:config_value=8'h01;
            2,10:config_value=8'h03;3:config_value=8'h09;
            5:config_value=8'h08;
            default:config_value=0;
        endcase
    endfunction
    i2c_register_master #(.REGISTER_BYTES(1),.QUARTER_CYCLES(I2C_QUARTER),
        .TIMEOUT_CYCLES(CLK_HZ/100)) bus(
        .clk(clk),.rst_n(rst_n),.start(bus_start),.read_request(bus_read),
        .device_address(ADDRESS),.register_address(bus_register),
        .read_length(bus_length),.write_data(bus_write),.scl(scl),.sda(sda),
        .busy(busy),.done(done),.error(error),.read_data(data));
    task fault;
        input [2:0] code;
        begin
            ready<=0;fault_code<=code;
            fault_count<=fault_count==255 ? 8'd255 : fault_count+1'b1;
            state<=RETRY;timer<=0;
        end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=BOOT;config_index<=0;timer<=0;age_ms<=0;mpu6500<=0;
            ready<=0;sample_valid<=0;sample_sequence<=0;
            ax<=0;ay<=0;az<=0;gx<=0;gy<=0;gz<=0;
            fault_count<=0;fault_code<=0;bus_start<=0;bus_read<=1;
            bus_register<=0;bus_length<=1;bus_write<=0;
        end else begin
            bus_start<=0;sample_valid<=0;
            if(tick_ms)begin
                if(timer!=65535)timer<=timer+1'b1;
                if(ready && age_ms!=65535)age_ms<=age_ms+1'b1;
            end
            case(state)
                BOOT:if(timer>=POWER_WAIT_MS)begin state<=RESET_START;timer<=0;end
                RESET_START:if(!busy)begin
                    bus_register<=16'h006b;bus_write<=8'h80;bus_read<=0;
                    bus_start<=1;state<=RESET_DONE;
                end
                RESET_DONE:if(done)begin
                    if(error)fault(1);else begin state<=RESET_WAIT;timer<=0;end
                end
                RESET_WAIT:if(timer>=RESET_WAIT_MS)state<=ID_START;
                ID_START:if(!busy)begin
                    bus_register<=16'h0075;bus_length<=1;bus_read<=1;
                    bus_start<=1;state<=ID_DONE;
                end
                ID_DONE:if(done)begin
                    if(error)fault(1);
                    else if(data[7:0]!=8'h68 && data[7:0]!=8'h70)fault(2);
                    else begin mpu6500<=data[7:0]==8'h70;config_index<=0;state<=WRITE_START;end
                end
                WRITE_START:if(!busy)begin
                    bus_register<={8'd0,config_register(config_index)};
                    bus_write<=config_value(config_index);bus_read<=0;
                    bus_start<=1;state<=WRITE_DONE;
                end
                WRITE_DONE:if(done)begin
                    if(error)fault(1);else state<=READBACK_START;
                end
                READBACK_START:if(!busy)begin
                    bus_read<=1;bus_length<=1;bus_start<=1;state<=READBACK_DONE;
                end
                READBACK_DONE:if(done)begin
                    if(error)fault(1);
                    else if(data[7:0]!=config_value(config_index))fault(3);
                    else if(config_index==0)begin state<=WAKE_WAIT;timer<=0;end
                    // 6500 adds ACCEL_CONFIG2=03; 6050 never accesses 1D.
                    else if(config_index==10 || (config_index==9 && !mpu6500))begin
                        ready<=1;fault_code<=0;age_ms<=0;timer<=0;state<=POLL_WAIT;
                    end else begin config_index<=config_index+1'b1;state<=WRITE_START;end
                end
                WAKE_WAIT:if(timer>=(mpu6500 ? WAKE_WAIT_6500_MS : WAKE_WAIT_MS))begin config_index<=1;state<=WRITE_START;end
                POLL_WAIT:if(timer>=POLL_MS)begin state<=STATUS_START;timer<=0;end
                STATUS_START:if(!busy)begin
                    bus_register<=16'h003a;bus_length<=1;bus_read<=1;
                    bus_start<=1;state<=STATUS_DONE;
                end
                STATUS_DONE:if(done)begin
                    if(error)fault(1);
                    else if(data[0])state<=DATA_START;
                    else begin state<=POLL_WAIT;timer<=0;end
                end
                DATA_START:if(!busy)begin
                    bus_register<=16'h003b;bus_length<=14;bus_read<=1;
                    bus_start<=1;state<=DATA_DONE;
                end
                DATA_DONE:if(done)begin
                    if(error)fault(1);
                    else begin
                        ax<={data[7:0],data[15:8]};ay<={data[23:16],data[31:24]};
                        az<={data[39:32],data[47:40]};
                        gx<={data[71:64],data[79:72]};gy<={data[87:80],data[95:88]};
                        gz<={data[103:96],data[111:104]};
                        sample_valid<=1;sample_sequence<=sample_sequence+1'b1;
                        age_ms<=0;timer<=0;state<=POLL_WAIT;
                    end
                end
                RETRY:if(timer>=RETRY_MS && !busy)begin timer<=0;state<=RESET_START;end
                default:state<=BOOT;
            endcase
            if(ready && age_ms>=STALE_MS && !(state==DATA_DONE && done && !error))fault(4);
        end
    end
endmodule
