// Minimal independent bring-up: probe both addresses before any writes.
// Only WHO_AM_I 68/70 selects a known MPU-6050/6500 register profile.
module mpu_lcd_diag_reader #(
    parameter integer CLK_HZ=50000000,I2C_QUARTER=125,
    parameter integer POWER_MS=200,RESET_MS=200,WAKE_MS=50,
    parameter integer RETRY_MS=1000,POLL_MS=5,STALE_MS=100
)(input wire clk,rst_n,tick_ms,inout wire scl,sda,
  output reg ack68,ack69,id68_valid,id69_valid,
  output reg [7:0] id68,id69,selected_address,selected_id,
  output reg [3:0] error68,error69,status,last_error,
  output reg [4:0] step,last_fault_step,
  output reg [7:0] last_register,expected_value,actual_value,
  output reg [31:0] sample_count,fault_count,
  output reg [15:0] sample_age,
  output reg [95:0] axes,
  output reg idle_scl,idle_sda,
  output reg sample_valid);
    localparam BOOT=0,SCAN68_START=1,SCAN68_DONE=2,SCAN69_START=3,SCAN69_DONE=4,
        SELECT=5,RESET_START=6,RESET_DONE=7,RESET_WAIT=8,
        WRITE_START=9,WRITE_DONE=10,VERIFY_START=11,VERIFY_DONE=12,
        WAKE_WAIT=13,POLL_WAIT=14,POLL_START=15,POLL_DONE=16,
        DATA_START=17,DATA_DONE=18,RETRY=19;
    // status: 0 search,1 no ACK,2 bad ID,3 configuring,4 config/bus error,
    // 5 stale,6 collecting,7 PASS (>=10 fresh packets).
    reg [15:0] timer;
    reg [3:0] config_index,session_packets;
    reg start,read_request;
    reg [6:0] address;
    reg [15:0] reg_address;
    reg [4:0] length;
    reg [7:0] write_byte;
    wire bus_busy,bus_done,bus_error;
    wire [127:0] data;
    wire [3:0] bus_acks,bus_code;
    reg [1:0] scl_sync,sda_sync;
    wire known68=id68_valid && (id68==8'h68 || id68==8'h70);
    wire known69=id69_valid && (id69==8'h68 || id69==8'h70);
    mpu_diag_i2c_master #(.REGISTER_BYTES(1),.QUARTER_CYCLES(I2C_QUARTER),
        .TIMEOUT_CYCLES(CLK_HZ/100)) bus(
        .clk(clk),.rst_n(rst_n),.start(start),.read_request(read_request),
        .device_address(address),.register_address(reg_address),.read_length(length),
        .write_data(write_byte),.scl(scl),.sda(sda),.busy(bus_busy),.done(bus_done),
        .error(bus_error),.read_data(data),.ack_bits(bus_acks),.error_code(bus_code));
    function [7:0] config_reg;
        input [3:0] n;
        case(n)
            0:config_reg=8'h6b;1:config_reg=8'h6c;2:config_reg=8'h1a;
            3:config_reg=8'h19;4:config_reg=8'h1b;5:config_reg=8'h1c;
            6:config_reg=8'h23;7:config_reg=8'h6a;8:config_reg=8'h37;
            9:config_reg=8'h38;default:config_reg=8'h1d;
        endcase
    endfunction
    function [7:0] config_data;
        input [3:0] n;
        case(n)
            0,9:config_data=1;2,10:config_data=3;3:config_data=9;
            5:config_data=8;default:config_data=0;
        endcase
    endfunction
    task fail;
        input [3:0] code;
        input [3:0] new_status;
        begin
            last_error<=code;status<=new_status;fault_count<=fault_count+1;
            last_fault_step<=step;
            step<=RETRY;timer<=0;
        end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            step<=BOOT;last_fault_step<=0;timer<=0;config_index<=0;session_packets<=0;
            start<=0;read_request<=1;address<=7'h68;reg_address<=16'h75;
            length<=1;write_byte<=0;ack68<=0;ack69<=0;id68_valid<=0;id69_valid<=0;
            id68<=0;id69<=0;selected_address<=0;selected_id<=0;error68<=0;error69<=0;
            status<=0;last_error<=0;last_register<=8'h75;expected_value<=8'h68;actual_value<=0;
            sample_count<=0;fault_count<=0;sample_age<=16'hffff;axes<=0;
            idle_scl<=1;idle_sda<=1;scl_sync<=3;sda_sync<=3;sample_valid<=0;
        end else begin
            scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};
            start<=0;sample_valid<=0;
            if(tick_ms)begin
                if(timer!=16'hffff)timer<=timer+1'b1;
                if(sample_age!=16'hffff)sample_age<=sample_age+1'b1;
            end
            case(step)
                BOOT:if(timer>=POWER_MS)begin timer<=0;step<=SCAN68_START;end
                SCAN68_START:if(!bus_busy)begin
                    status<=0;idle_scl<=scl_sync[1];idle_sda<=sda_sync[1];
                    address<=7'h68;reg_address<=16'h75;read_request<=1;length<=1;
                    last_register<=8'h75;expected_value<=8'h68;
                    start<=1;step<=SCAN68_DONE;
                end
                SCAN68_DONE:if(bus_done)begin
                    ack68<=bus_acks[0];id68_valid<=!bus_error;id68<=data[7:0];
                    error68<=bus_code;step<=SCAN69_START;
                end
                SCAN69_START:if(!bus_busy)begin
                    address<=7'h69;reg_address<=16'h75;read_request<=1;length<=1;
                    start<=1;step<=SCAN69_DONE;
                end
                SCAN69_DONE:if(bus_done)begin
                    ack69<=bus_acks[0];id69_valid<=!bus_error;id69<=data[7:0];
                    error69<=bus_code;step<=SELECT;
                end
                SELECT:begin
                    if(known68 || known69)begin
                        address<=known68 ? 7'h68 : 7'h69;
                        selected_address<=known68 ? 8'h68 : 8'h69;
                        selected_id<=known68 ? id68 : id69;
                        last_error<=0;status<=3;session_packets<=0;
                        step<=RESET_START;
                    end else begin
                        selected_address<=0;selected_id<=0;actual_value<=id68_valid ? id68 : id69;
                        last_error<=id68_valid || id69_valid ? 4'd10 :
                                    error68==5 || error69==5 ? 4'd5 :
                                    error68==6 || error69==6 ? 4'd6 : error68;
                        status<=id68_valid || id69_valid ? 2 : 1;
                        last_fault_step<=SELECT;
                        fault_count<=fault_count+1;timer<=0;step<=RETRY;
                    end
                end
                RESET_START:if(!bus_busy)begin
                    reg_address<=16'h6b;write_byte<=8'h80;read_request<=0;
                    last_register<=8'h6b;expected_value<=8'h80;
                    start<=1;step<=RESET_DONE;
                end
                RESET_DONE:if(bus_done)begin
                    if(bus_error)fail(bus_code,4);
                    else begin timer<=0;step<=RESET_WAIT;end
                end
                RESET_WAIT:if(timer>=RESET_MS)begin config_index<=0;step<=WRITE_START;end
                WRITE_START:if(!bus_busy)begin
                    reg_address<={8'd0,config_reg(config_index)};
                    write_byte<=config_data(config_index);read_request<=0;
                    last_register<=config_reg(config_index);expected_value<=config_data(config_index);
                    start<=1;step<=WRITE_DONE;
                end
                WRITE_DONE:if(bus_done)begin
                    if(bus_error)fail(bus_code,4);else step<=VERIFY_START;
                end
                VERIFY_START:if(!bus_busy)begin
                    read_request<=1;length<=1;start<=1;step<=VERIFY_DONE;
                end
                VERIFY_DONE:if(bus_done)begin
                    actual_value<=data[7:0];
                    if(bus_error)fail(bus_code,4);
                    else if(data[7:0]!=config_data(config_index))fail(7,4);
                    else if(config_index==0)begin timer<=0;step<=WAKE_WAIT;end
                    // 6500 has a separate accel DLPF. 6050 never touches 1D.
                    else if(config_index==10 || (config_index==9 && selected_id==8'h68))begin
                        timer<=0;sample_age<=0;status<=6;step<=POLL_WAIT;
                    end
                    else begin config_index<=config_index+1'b1;step<=WRITE_START;end
                end
                WAKE_WAIT:if(timer>=WAKE_MS)begin config_index<=1;step<=WRITE_START;end
                POLL_WAIT:if(sample_age>=STALE_MS)fail(8,5);
                    else if(timer>=POLL_MS)begin timer<=0;step<=POLL_START;end
                POLL_START:if(!bus_busy)begin
                    reg_address<=16'h3a;last_register<=8'h3a;
                    read_request<=1;length<=1;start<=1;step<=POLL_DONE;
                end
                POLL_DONE:if(bus_done)begin
                    if(bus_error)fail(bus_code,4);
                    else if(data[0])step<=DATA_START;else step<=POLL_WAIT;
                end
                DATA_START:if(!bus_busy)begin
                    reg_address<=16'h3b;last_register<=8'h3b;read_request<=1;
                    length<=14;start<=1;step<=DATA_DONE;
                end
                DATA_DONE:if(bus_done)begin
                    if(bus_error)fail(bus_code,4);
                    else begin
                        axes<={data[7:0],data[15:8],data[23:16],data[31:24],
                               data[39:32],data[47:40],data[71:64],data[79:72],
                               data[87:80],data[95:88],data[103:96],data[111:104]};
                        sample_count<=sample_count+1;sample_age<=0;sample_valid<=1;
                        if(session_packets<10)session_packets<=session_packets+1'b1;
                        status<=session_packets>=9 ? 7 : 6;
                        timer<=0;step<=POLL_WAIT;
                    end
                end
                RETRY:if(timer>=RETRY_MS && !bus_busy)begin timer<=0;step<=SCAN68_START;end
                default:begin timer<=0;step<=BOOT;end
            endcase
        end
    end
endmodule
