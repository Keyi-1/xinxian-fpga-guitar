// XG3 fixed 32-byte packets, stop-and-wait, CRC32/ISO-HDLC. A DATA
// packet carries one v2 event. No byte-level backpressure is assumed.
// See docs/P3_WRITABLE_SONG_IMPORT.md for the frozen wire layout.
module game_p3_protocol #(parameter integer FRAME_TIMEOUT=25000000)(
    input wire clk,rst_n,rx_valid,rx_error,input wire [7:0] rx_data,
    output wire tx_valid,output reg [7:0] tx_data,input wire tx_ready,
    output wire cmd_valid,input wire cmd_ready,output reg [1:0] cmd,
    output wire [2:0] slot,output wire [11:0] event_count,
    output wire [31:0] duration,expected_crc,output wire [1:0] timbre,
    output wire [127:0] record_data,
    input wire response_valid,input wire [3:0] response_code,input wire locked,
    input wire [4:0] overlay_valid,input wire [479:0] overlay_data,
    output reg [15:0] error_count);
    localparam SYNC=0,RX=1,VERIFY=2,ISSUE=3,WAIT=4,TX=5;
    reg [2:0] state;
    reg [1:0] magic_index;
    reg [5:0] index;
    reg [7:0] version,opcode;
    reg [15:0] packet_session,packet_sequence,reserved;
    reg [127:0] payload,reply_payload,cached_payload;
    reg [31:0] crc,packet_crc,tx_crc,timeout_count;
    reg [15:0] current_session,next_sequence,last_sequence;
    reg [31:0] last_crc;
    reg [7:0] last_opcode;
    reg session_valid,cache_valid;
    reg [7:0] fifo[0:15];
    reg [3:0] wp,rp;
    reg [4:0] used;
    reg poisoned;
    wire pop=used!=0 && (state==SYNC || state==RX) && !poisoned;
    wire push=rx_valid && (used<16 || pop);
    wire [7:0] byte_value=fifo[rp];
    wire [3:0] payload_byte=index[3:0]-4'd10;
    wire [31:0] final_tx_crc=tx_crc^32'hffffffff;
    wire qv,qp,qt;wire [10:0] qb;wire [11:0] qc;wire [31:0] qd,qs;wire [1:0] qi;
    wire [95:0] query_descriptor={7'd0,qi,qd,qc,qb,qs};
    game_p3_catalog query(.slot(payload[2:0]),.overlay_valid(overlay_valid),.overlay_data(overlay_data),
        .valid(qv),.playable(qp),.test_only(qt),.base(qb),.event_count(qc),.duration(qd),.progress_step(qs),.timbre(qi));
    assign tx_valid=state==TX;
    assign cmd_valid=state==ISSUE;
    assign slot=payload[2:0];assign timbre=payload[9:8];
    assign event_count=payload[27:16];
    assign duration=payload[63:32];assign expected_crc=payload[95:64];
    assign record_data=payload;
    function [31:0] crc_byte;
        input [31:0] prior;input [7:0] b;reg [31:0] v;integer k;
        begin v=prior^{24'd0,b};for(k=0;k<8;k=k+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
    endfunction
    function [7:0] magic;
        input [1:0] pos;
        begin case(pos)0:magic=8'h58;1:magic=8'h47;2:magic=8'h33;default:magic=8'h21;endcase end
    endfunction
    // All response payloads begin with one status byte. The remaining bytes
    // depend on the command and are cached exactly for lost-ACK retries.
    task respond;
        input [7:0] status;input [119:0] body;input remember;
        begin
            reply_payload<={body,status};index<=0;tx_crc<=32'hffffffff;state<=TX;
            if(status!=0 && error_count!=65535)error_count<=error_count+1'b1;
            if(remember)begin
                cache_valid<=1;last_sequence<=packet_sequence;last_opcode<=opcode;last_crc<=packet_crc;
                cached_payload<={body,status};next_sequence<=packet_sequence+1'b1;
            end
        end
    endtask
    always @*begin
        case(index)
            0,1,2,3:tx_data=magic(index[1:0]);
            4:tx_data=3;5:tx_data=opcode|8'h80;
            6:tx_data=packet_session[7:0];7:tx_data=packet_session[15:8];
            8:tx_data=packet_sequence[7:0];9:tx_data=packet_sequence[15:8];
            26,27:tx_data=0;
            28,29,30,31:tx_data=final_tx_crc[{index[1:0],3'b000}+:8];
            default:tx_data=reply_payload[{payload_byte,3'b000}+:8];
        endcase
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=SYNC;magic_index<=0;index<=0;version<=0;opcode<=0;packet_session<=0;packet_sequence<=0;
            payload<=0;reply_payload<=0;cached_payload<=0;reserved<=0;crc<=32'hffffffff;packet_crc<=0;tx_crc<=32'hffffffff;
            timeout_count<=0;current_session<=0;next_sequence<=0;last_sequence<=0;last_crc<=0;last_opcode<=0;
            session_valid<=0;cache_valid<=0;cmd<=0;error_count<=0;wp<=0;rp<=0;used<=0;poisoned<=0;
        end else begin
            if(push)begin fifo[wp]<=rx_data;wp<=wp+1'b1;end
            if(pop)rp<=rp+1'b1;
            case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:begin end endcase
            if(rx_error || (rx_valid && !push))begin poisoned<=1;if(error_count!=65535)error_count<=error_count+1'b1;end
            if(pop || state!=RX)timeout_count<=0;
            else if(timeout_count<FRAME_TIMEOUT)timeout_count<=timeout_count+1'b1;
            if((poisoned || timeout_count>=FRAME_TIMEOUT) && (state==SYNC || state==RX))begin
                state<=SYNC;magic_index<=0;poisoned<=0;used<=0;rp<=wp;timeout_count<=0;
                if(timeout_count>=FRAME_TIMEOUT && error_count!=65535)error_count<=error_count+1'b1;
            end else case(state)
                SYNC:if(pop)begin
                    if(byte_value==magic(magic_index))begin
                        if(magic_index==3)begin state<=RX;index<=4;crc<=32'hffffffff;magic_index<=0;end
                        else magic_index<=magic_index+1'b1;
                    end else magic_index<=byte_value==8'h58 ? 1 : 0;
                end
                RX:if(pop)begin
                    if(index<28)crc<=crc_byte(crc,byte_value);
                    case(index)
                        4:version<=byte_value;5:opcode<=byte_value;
                        6:packet_session[7:0]<=byte_value;7:packet_session[15:8]<=byte_value;
                        8:packet_sequence[7:0]<=byte_value;9:packet_sequence[15:8]<=byte_value;
                        26:reserved[7:0]<=byte_value;27:reserved[15:8]<=byte_value;
                        28,29,30,31:packet_crc[{index[1:0],3'b000}+:8]<=byte_value;
                        default:payload[{payload_byte,3'b000}+:8]<=byte_value;
                    endcase
                    if(index==31)state<=VERIFY;else index<=index+1'b1;
                end
                VERIFY:begin
                    if((crc^32'hffffffff)!=packet_crc)respond(12,0,0);
                    else if(version!=3 || reserved!=0 || packet_session==0)respond(11,0,0);
                    else if(session_valid && packet_session==current_session && cache_valid && packet_sequence==last_sequence)begin
                        if(opcode==last_opcode && packet_crc==last_crc)begin reply_payload<=cached_payload;index<=0;tx_crc<=32'hffffffff;state<=TX;end
                        else respond(13,0,0);
                    end else if(opcode==1 && packet_sequence==0 && !locked && (!session_valid || packet_session!=current_session))begin
                        current_session<=packet_session;session_valid<=1;
                        // bytes1..: event format2, five slots, first runtime row,
                        // total capacity2048, max MIDI79, min MIDI50, 48kHz.
                        respond(0,{16'h0001,32'd48000,8'd79,8'd50,16'd2048,16'd703,8'd32,8'd5,8'd2},1);
                    end else if(!session_valid || packet_session!=current_session || packet_sequence!=next_sequence)respond(13,0,0);
                    else if(opcode==2)begin
                        if(payload[7:0]>=5 || payload[127:8]!=0)respond(6,0,0);
                        else respond(0,{8'd0,4'd0,qt,overlay_valid[payload[2:0]],qp,qv,payload[7:0],query_descriptor},1);
                    end else if(opcode==7)respond(0,{64'd0,error_count,next_sequence,3'd0,overlay_valid,7'd0,locked,8'd0},1);
                    else if(opcode==3)begin
                        if(payload[7:0]>=5 || payload[15:8]>=3 || payload[31:16]>2048 || payload[127:96]!=0)respond(6,0,0);
                        else begin cmd<=0;state<=ISSUE;end
                    end else if(opcode==4)begin cmd<=1;state<=ISSUE;end
                    else if((opcode==5 || opcode==6) && payload==0)begin cmd<=opcode==5 ? 2'd2 : 2'd3;state<=ISSUE;end
                    else respond(10,0,0);
                end
                ISSUE:if(cmd_ready)state<=WAIT;
                WAIT:if(response_valid)respond({4'd0,response_code},0,response_code==0);
                TX:if(tx_ready)begin
                    if(index>=4 && index<28)tx_crc<=crc_byte(tx_crc,tx_data);
                    if(index==31)begin state<=SYNC;magic_index<=0;end else index<=index+1'b1;
                end
                default:state<=SYNC;
            endcase
        end
    end
endmodule
