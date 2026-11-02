module game_p3_service #(parameter integer UART_CLKS_PER_BIT=434)(
    input wire clk,rst_n,audio_clk,audio_rst_n,rx,output wire tx,
    input wire audio_idle,menu_idle,frame_begin,
    output wire locked,write_enable,output wire [10:0] write_address,
    output wire [95:0] write_data,
    output wire verify_read,output wire [10:0] verify_address,input wire [95:0] verify_data,
    output wire [4:0] system_valid,audio_valid,
    output wire [479:0] system_data,audio_data);
    reg idle_meta,idle_sync;
    always @(posedge clk)begin
        if(!rst_n)begin idle_meta<=0;idle_sync<=0;end
        else begin idle_meta<=audio_idle;idle_sync<=idle_meta;end
    end
    wire rx_valid,rx_error,tx_valid,tx_ready,cmd_valid,cmd_ready,response_valid,commit_valid,cdc_ready;
    wire [7:0] rx_data,tx_data;wire [1:0] cmd,timbre;wire [2:0] slot,commit_slot;
    wire [11:0] count;wire [31:0] duration,expected_crc;wire [127:0] record_data;
    wire [3:0] response_code;wire [95:0] descriptor;
    game_p3_uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart(.clk(clk),.rst_n(rst_n),.rx(rx),.tx(tx),
        .rx_valid(rx_valid),.rx_data(rx_data),.framing_error(rx_error),.tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready));
    game_p3_protocol protocol(.clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),.rx_error(rx_error),.rx_data(rx_data),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd(cmd),
        .slot(slot),.event_count(count),.duration(duration),.expected_crc(expected_crc),.timbre(timbre),.record_data(record_data),
        .response_valid(response_valid),.response_code(response_code),.locked(locked),.overlay_valid(system_valid),.overlay_data(system_data),.error_count(),
        .query_request(),.query_slot(),.query_ready(1'b0),.query_body(120'd0),
        .context_load(1'b0),.context_data(234'd0),.context_state(),.frame_idle(),.rx_ready());
    game_p3_import importer(.clk(clk),.rst_n(rst_n),.import_allowed(idle_sync && menu_idle),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd(cmd),.slot(slot),.event_count(count),.duration(duration),.expected_crc(expected_crc),.timbre(timbre),.record_data(record_data),
        .response_valid(response_valid),.response_code(response_code),.locked(locked),.write_enable(write_enable),.write_address(write_address),.write_data(write_data),
        .verify_read(verify_read),.verify_address(verify_address),.verify_data(verify_data),
        .commit_valid(commit_valid),.commit_ready(cdc_ready && frame_begin),.commit_slot(commit_slot),.commit_descriptor(descriptor),.overlay_valid(system_valid),.overlay_data(system_data));
    game_p3_catalog_cdc catalog_cdc(.src_clk(clk),.src_rst_n(rst_n),.valid(commit_valid),.slot(commit_slot),.descriptor(descriptor),.ready(cdc_ready),
        .dst_clk(audio_clk),.dst_rst_n(audio_rst_n),.overlay_valid(audio_valid),.overlay_data(audio_data));
endmodule
