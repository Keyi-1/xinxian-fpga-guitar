// Parallel physical links and complete-frame staging; one TDM protocol kernel.
// Only the inactive endpoint's session/cache context is saved outside the core.
// UART serializers remain independent, and the score bank/importer stay atomic.
module game_p3_dual_service #(
    parameter integer BLE_CLKS_PER_BIT=5208, USB_CLKS_PER_BIT=434,
    parameter integer IMPORT_TIMEOUT_CYCLES=250000000
)(
    input wire clk,rst_n,audio_clk,audio_rst_n,
    input wire ble_rx,usb_rx,output wire ble_tx,usb_tx,
    input wire audio_idle,menu_idle,frame_begin,
    output wire locked,write_enable,output wire [10:0] write_address,
    output wire [95:0] write_data,
    output wire verify_read,output wire [10:0] verify_address,input wire [95:0] verify_data,
    output wire [4:0] system_valid,audio_valid,
    output wire [479:0] system_data,audio_data
);
    reg idle_meta,idle_sync;
    always @(posedge clk)begin
        if(!rst_n)begin idle_meta<=0;idle_sync<=0;end
        else begin idle_meta<=audio_idle;idle_sync<=idle_meta;end
    end
    wire [1:0] rx_valid,rx_error,tx_ready,tx_pin,packet_ready,packet_take;
    wire [15:0] rx_data;
    wire [447:0] packet_data;
    wire [31:0] frontend_errors;
    wire [1:0] query_request={packet_ready[1] && packet_data[239:232]==2,
                              packet_ready[0] && packet_data[15:8]==2};
    assign ble_tx=tx_pin[0];assign usb_tx=tx_pin[1];
    reg active_port,round_robin,owner;
    wire core_tx_valid,core_idle,core_rx_ready;
    wire [7:0] core_tx_data;
    genvar i;
    generate for(i=0;i<2;i=i+1)begin:link
        game_p3_uart #(.CLKS_PER_BIT(i==0 ? BLE_CLKS_PER_BIT : USB_CLKS_PER_BIT)) uart(
            .clk(clk),.rst_n(rst_n),.rx(i==0 ? ble_rx : usb_rx),.tx(tx_pin[i]),
            .rx_valid(rx_valid[i]),.rx_data(rx_data[i*8+:8]),.framing_error(rx_error[i]),
            .tx_valid(core_tx_valid && active_port==i),.tx_data(core_tx_data),.tx_ready(tx_ready[i]));
        game_p3_frame_rx receiver(.clk(clk),.rst_n(rst_n),.rx_valid(rx_valid[i]),.rx_error(rx_error[i]),.rx_data(rx_data[i*8+:8]),
            .take(packet_take[i]),.ready(packet_ready[i]),.data(packet_data[i*224+:224]),.errors(frontend_errors[i*16+:16]));
    end endgenerate
    localparam IDLE=0,START=1,REPLAY=2,WAIT_REPLY=3;
    reg [1:0] state;
    reg [4:0] replay_index;
    reg replay_phase,reply_seen,next_port;
    wire context_load=state==START;
    reg [233:0] inactive_context;
    wire [233:0] core_context;
    reg [15:0] error_seen0,error_seen1;
    wire selected=locked && packet_ready[owner] ? owner :
                  (packet_ready==2'b11 ? round_robin : packet_ready[1]);
    wire [233:0] incoming_context=next_port==active_port ? core_context : inactive_context;
    wire [15:0] selected_errors=next_port ? frontend_errors[31:16] : frontend_errors[15:0];
    wire [15:0] error_delta=selected_errors-(next_port ? error_seen1 : error_seen0);
    wire [16:0] error_sum={1'b0,incoming_context[233:218]}+{1'b0,error_delta};
    wire [233:0] prepared_context={error_sum[16] ? 16'hffff : error_sum[15:0],incoming_context[217:0]};
    wire replay_valid=state==REPLAY && !replay_phase && core_rx_ready;
    wire [4:0] byte_index=replay_index-5'd4;
    wire [223:0] frame0=packet_data[223:0],frame1=packet_data[447:224];
    wire [7:0] byte0=frame0[{byte_index,3'b000}+:8];
    wire [7:0] byte1=frame1[{byte_index,3'b000}+:8];
    reg [7:0] replay_data;
    always @*begin
        case(replay_index)
            0:replay_data=8'h58;1:replay_data=8'h47;2:replay_data=8'h33;3:replay_data=8'h21;
            default:replay_data=active_port ? byte1 : byte0;
        endcase
    end
    assign packet_take=replay_valid && replay_index==31 ? (active_port ? 2'b10 : 2'b01) : 2'b00;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;active_port<=0;round_robin<=0;replay_index<=0;replay_phase<=0;
            reply_seen<=0;next_port<=0;inactive_context<=0;error_seen0<=0;error_seen1<=0;
        end else begin
            case(state)
                IDLE:if(core_idle && |packet_ready)begin
                    next_port<=selected;state<=START;
                end
                START:begin
                    // Both sides of the swap sample old Q on this edge.
                    if(next_port!=active_port)inactive_context<=core_context;
                    active_port<=next_port;
                    if(next_port)error_seen1<=selected_errors;else error_seen0<=selected_errors;
                    replay_index<=0;replay_phase<=0;reply_seen<=0;state<=REPLAY;
                end
                REPLAY:begin
                    if(replay_phase)replay_phase<=0;
                    else if(core_rx_ready)begin
                        replay_phase<=1;
                        if(replay_index==31)state<=WAIT_REPLY;
                        else replay_index<=replay_index+1'b1;
                    end
                end
                WAIT_REPLY:begin
                    if(core_tx_valid)reply_seen<=1;
                    if(reply_seen && core_idle)begin round_robin<=!active_port;state<=IDLE;end
                end
                default:state<=IDLE;
            endcase
        end
    end
    wire cmd_valid,cmd_ready,response_valid;
    wire [1:0] command,timbre;
    wire [2:0] slot;
    wire [11:0] count;
    wire [31:0] duration,expected_crc;
    wire [127:0] record_data;
    wire [3:0] response_code;
    game_p3_protocol #(.DIRECT_INPUT(1),.CONTEXT_SWITCH(1)) core(
        .clk(clk),.rst_n(rst_n),.rx_valid(replay_valid),.rx_error(1'b0),.rx_data(replay_data),
        .tx_valid(core_tx_valid),.tx_data(core_tx_data),.tx_ready(active_port ? tx_ready[1] : tx_ready[0]),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd(command),.slot(slot),.event_count(count),.duration(duration),
        .expected_crc(expected_crc),.timbre(timbre),.record_data(record_data),.response_valid(response_valid),.response_code(response_code),
        .locked(locked),.overlay_valid(system_valid),.overlay_data(system_data),.error_count(),
        .query_request(),.query_slot(),.query_ready(1'b0),.query_body(120'd0),
        .context_load(context_load),.context_data(prepared_context),.context_state(core_context),.frame_idle(core_idle),.rx_ready(core_rx_ready));
    reg pending,rejected;
    wire importer_ready,importer_response;
    wire [3:0] importer_code;
    wire reject=locked && active_port!=owner;
    assign cmd_ready=!pending && (reject || importer_ready);
    assign response_valid=(pending && importer_response) || rejected;
    assign response_code=rejected ? 4'd1 : importer_code;
    always @(posedge clk)begin
        if(!rst_n)begin owner<=0;pending<=0;rejected<=0;end
        else begin
            rejected<=0;
            if(pending && importer_response)pending<=0;
            if(cmd_valid && cmd_ready)begin
                if(reject)rejected<=1;
                else begin pending<=1;if(command==0)owner<=active_port;end
            end
        end
    end
    wire commit_valid,cdc_ready;
    wire [2:0] commit_slot;
    wire [95:0] descriptor;
    game_p3_import #(.TIMEOUT_CYCLES(IMPORT_TIMEOUT_CYCLES)) importer(
        .clk(clk),.rst_n(rst_n),.import_allowed(idle_sync && menu_idle),
        .cmd_valid(cmd_valid && !pending && !reject),.cmd_ready(importer_ready),.cmd(command),
        .slot(slot),.event_count(count),.duration(duration),.expected_crc(expected_crc),.timbre(timbre),.record_data(record_data),
        .response_valid(importer_response),.response_code(importer_code),.locked(locked),
        .write_enable(write_enable),.write_address(write_address),.write_data(write_data),
        .verify_read(verify_read),.verify_address(verify_address),.verify_data(verify_data),
        .commit_valid(commit_valid),.commit_ready(cdc_ready && frame_begin),
        .commit_slot(commit_slot),.commit_descriptor(descriptor),.overlay_valid(system_valid),.overlay_data(system_data));
    game_p3_catalog_cdc catalog_cdc(
        .src_clk(clk),.src_rst_n(rst_n),.valid(commit_valid),.slot(commit_slot),.descriptor(descriptor),.ready(cdc_ready),
        .dst_clk(audio_clk),.dst_rst_n(audio_rst_n),.overlay_valid(audio_valid),.overlay_data(audio_data));
endmodule

// One complete XG3 packet per port. Magic is regenerated for replay, so only
// bytes4..31 occupy registers. No BSRAM/SSRAM and no recorded audio are used.
module game_p3_frame_rx #(parameter integer FRAME_TIMEOUT=25000000)(
    input wire clk,rst_n,rx_valid,rx_error,input wire [7:0] rx_data,input wire take,
    output reg ready,output reg [223:0] data,output reg [15:0] errors
);
    localparam TIMER_BITS=$clog2(FRAME_TIMEOUT+1);
    reg [TIMER_BITS-1:0] timeout_count;
    reg [1:0] magic_index;
    reg [4:0] index;
    reg receiving;
    function [7:0] magic(input [1:0] n);
        begin case(n)0:magic=8'h58;1:magic=8'h47;2:magic=8'h33;default:magic=8'h21;endcase end
    endfunction
    always @(posedge clk)begin
        if(!rst_n)begin ready<=0;errors<=0;magic_index<=0;index<=0;receiving<=0;timeout_count<=0;end
        else begin
            if(take)begin ready<=0;receiving<=0;magic_index<=0;index<=0;timeout_count<=0;end
            if(rx_error)begin
                if(errors!=65535)errors<=errors+1'b1;
                if(!ready)begin receiving<=0;magic_index<=0;timeout_count<=0;end
            end else if(!ready && rx_valid)begin
                timeout_count<=0;
                if(!receiving)begin
                    if(rx_data==magic(magic_index))begin
                        if(magic_index==3)begin receiving<=1;magic_index<=0;index<=0;end
                        else magic_index<=magic_index+1'b1;
                    end else magic_index<=rx_data==8'h58 ? 1 : 0;
                end else begin
                    data[{index,3'b000}+:8]<=rx_data;
                    if(index==27)begin ready<=1;receiving<=0;magic_index<=0;end
                    else index<=index+1'b1;
                end
            end else if(ready && rx_valid)begin
                // A compliant stop-and-wait host has no next packet yet.
                if(errors!=65535)errors<=errors+1'b1;
            end else if(receiving)begin
                if(timeout_count>=FRAME_TIMEOUT)begin
                    receiving<=0;magic_index<=0;timeout_count<=0;
                    if(errors!=65535)errors<=errors+1'b1;
                end else timeout_count<=timeout_count+1'b1;
            end else timeout_count<=0;
        end
    end
endmodule
