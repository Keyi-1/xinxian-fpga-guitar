// One outstanding command; hold cmd_valid/data until cmd_ready. A response
// terminates every accepted command. Tentative data is never published early.
// The immutable initial 703 records are reserved across reset. Imported slots
// share the remaining 1345 records and are volatile. Replacing a song requires
// enough free contiguous space for BOTH old and new versions until commit.
module game_p3_import #(
    parameter integer RESERVED_RECORDS=703,
    parameter integer TIMEOUT_CYCLES=250000000
)(input wire clk,rst_n,import_allowed,
  input wire cmd_valid,output wire cmd_ready,input wire [1:0] cmd,
  input wire [2:0] slot,input wire [11:0] event_count,
  input wire [31:0] duration,expected_crc,input wire [1:0] timbre,
  input wire [127:0] record_data,
  output reg response_valid,output reg [3:0] response_code,
  output wire locked,output reg write_enable,output reg [10:0] write_address,
  output reg [95:0] write_data,
  output wire verify_read,output wire [10:0] verify_address,input wire [95:0] verify_data,
  output wire commit_valid,input wire commit_ready,
  output reg [2:0] commit_slot,output reg [95:0] commit_descriptor,
  output reg [4:0] overlay_valid,output reg [479:0] overlay_data);
    // Commands BEGIN=0, RECORD=1, COMMIT=2, ABORT=3.
    // Errors OK=0 BUSY=1 NO_SPACE=2 LENGTH=3 CRC=4 ORDER=5 RANGE=6
    // DENSITY=7 TIMEOUT=8 STATE=9. UART framing errors are handled upstream.
    localparam IDLE=0,ALLOCATE=1,RECEIVE=2,CHECK=3,CRC=4,STORE=5,
               DIVIDE=6,PUBLISH=7,READBACK=8,READBACK_LATCH=9,READBACK_CRC=10,READBACK_CHECK=11;
    reg [3:0] state;
    reg session;
    reg [11:0] candidate,received,count;
    reg [31:0] total,crc_expected,crc_value,last_onset,timeout_count;
    reg [1:0] song_timbre;
    reg [127:0] record;
    reg [3:0] crc_byte;
    reg [31:0] lane_end[0:3],lane_last[0:3];
    reg [3:0] lane_seen;
    reg [3:0] lane_count[0:3];
    reg [2:0] lane_pointer[0:3];
    reg [31:0] lane_history[0:31];
    reg [31:0] oldest;
    reg [2:0] scan_slot;
    reg [31:0] dividend,quotient;
    reg [9:0] remainder;
    reg [5:0] divide_bit;
    wire [31:0] onset=record[31:0],length=record[63:32];
    wire [7:0] midi=record[71:64],lane_byte=record[79:72];
    wire [1:0] lane=record[73:72];
    wire [32:0] end_time={1'b0,onset}+{1'b0,length};
    // Do not use scan_slot*96 as a dynamic part-select index. Gowin mapped
    // that address arithmetic into a DSP and a 10k-LUT barrel selector.
    reg [22:0] allocation_entry;
    always @*begin
        case(scan_slot)
            0:allocation_entry=overlay_data[0*96+32+:23];
            1:allocation_entry=overlay_data[1*96+32+:23];
            2:allocation_entry=overlay_data[2*96+32+:23];
            3:allocation_entry=overlay_data[3*96+32+:23];
            4:allocation_entry=overlay_data[4*96+32+:23];
            default:allocation_entry=0;
        endcase
    end
    wire [11:0] allocation_base={1'b0,allocation_entry[10:0]};
    wire [12:0] allocation_end={2'd0,allocation_entry[10:0]}+{1'b0,allocation_entry[22:11]};
    wire [10:0] trial={remainder,dividend[31]};
    wire subtract=trial>=480;
    wire [31:0] next_quotient={quotient[30:0],subtract};
    assign cmd_ready=state==IDLE || state==RECEIVE;
    assign locked=session;
    assign commit_valid=state==PUBLISH;
    assign verify_read=state==READBACK;
    assign verify_address=candidate[10:0]+received[10:0];
    function [31:0] crc32_byte;
        input [31:0] prior;input [7:0] data;
        reg [31:0] value;integer b;
        begin value=prior^{24'd0,data};
            for(b=0;b<8;b=b+1)value=value[0] ? (value>>1)^32'hedb88320 : value>>1;
            crc32_byte=value;
        end
    endfunction
    task reply;
        input [3:0] code;
        begin response_valid<=1;response_code<=code;end
    endtask
    task fail;
        input [3:0] code;
        begin reply(code);session<=0;state<=IDLE;end
    endtask
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;session<=0;response_valid<=0;response_code<=0;
            write_enable<=0;write_address<=0;write_data<=0;
            overlay_valid<=0;overlay_data<=0;commit_slot<=0;commit_descriptor<=0;
            candidate<=0;received<=0;count<=0;total<=0;crc_expected<=0;crc_value<=32'hffffffff;
            last_onset<=0;timeout_count<=0;song_timbre<=0;record<=0;crc_byte<=0;
            lane_seen<=0;oldest<=0;scan_slot<=0;dividend<=0;quotient<=0;remainder<=0;divide_bit<=0;
            for(i=0;i<4;i=i+1)begin lane_end[i]<=0;lane_last[i]<=0;lane_count[i]<=0;lane_pointer[i]<=0;end
        end else begin
            response_valid<=0;write_enable<=0;
            if(!session || state!=RECEIVE || (cmd_valid && cmd_ready))timeout_count<=0;
            else if(timeout_count<TIMEOUT_CYCLES)timeout_count<=timeout_count+1'b1;
            // Publication cannot be abandoned halfway through its CDC ack.
            if(session && state==RECEIVE && timeout_count>=TIMEOUT_CYCLES)fail(8);
            else if(session && state!=PUBLISH && !import_allowed)fail(1);
            else case(state)
                IDLE,RECEIVE:if(cmd_valid)begin
                    if(cmd==3)begin session<=0;state<=IDLE;reply(0);end
                    else if(cmd==0)begin
                        if(session || !import_allowed)reply(1);
                        else if(slot>=5 || event_count==0 || event_count>2048 || duration==0 || duration>28800000 || timbre>=3)reply(6);
                        else begin
                            commit_slot<=slot;count<=event_count;total<=duration;song_timbre<=timbre;crc_expected<=expected_crc;
                            candidate<=RESERVED_RECORDS;scan_slot<=0;received<=0;crc_value<=32'hffffffff;
                            lane_seen<=0;last_onset<=0;session<=1;state<=ALLOCATE;
                            for(i=0;i<4;i=i+1)begin lane_end[i]<=0;lane_last[i]<=0;lane_count[i]<=0;lane_pointer[i]<=0;end
                        end
                    end else if(!session)reply(9);
                    else if(cmd==1)begin
                        if(received>=count)fail(3);
                        else begin record<=record_data;state<=CHECK;
                            oldest<=lane_history[{record_data[73:72],lane_pointer[record_data[73:72]]}];end
                    end else if(received!=count)fail(3);
                    else if((crc_value^32'hffffffff)!=crc_expected)fail(4);
                    else begin
                        // Read actual BSRAM back before publishing. This also
                        // retains all96 bits/group IDs in the implemented bank.
                        received<=0;crc_value<=32'hffffffff;state<=READBACK;
                    end
                end
                ALLOCATE:begin
                    if({1'b0,candidate}+{1'b0,count}>2048)fail(2);
                    else if(scan_slot==5)begin state<=RECEIVE;reply(0);end
                    else if(overlay_valid[scan_slot] && {1'b0,candidate}<allocation_end && {1'b0,candidate}+{1'b0,count}>{1'b0,allocation_base})begin
                        candidate<=allocation_end[11:0];scan_slot<=0;
                    end else scan_slot<=scan_slot+1'b1;
                end
                CHECK:begin
                    if(midi<50 || midi>79 || lane_byte>3 || record[87:80]>3 || record[95:88]!=0 || record[127:112]!=0 ||
                       length==0 || end_time>{1'b0,total})fail(6);
                    // group_id is legal transport metadata and is retained.
                    else if(received!=0 && onset<last_onset)fail(5);
                    else if(lane_seen[lane] && (onset<lane_end[lane] || onset-lane_last[lane]<12000))fail(5);
                    else if(lane_count[lane]>=8 && onset-oldest<=108200)fail(7);
                    else begin crc_byte<=0;state<=CRC;end
                end
                CRC,READBACK_CRC:begin
                    crc_value<=crc32_byte(crc_value,record[{crc_byte,3'b000}+:8]);
                    if(crc_byte==15)begin
                        if(state==CRC)state<=STORE;
                        else if(received+1'b1==count)state<=READBACK_CHECK;
                        else begin received<=received+1'b1;state<=READBACK;end
                    end else crc_byte<=crc_byte+1'b1;
                end
                READBACK:state<=READBACK_LATCH;
                READBACK_LATCH:begin
                    record<={16'd0,verify_data[95:80],3'd0,verify_data[79:75],6'd0,verify_data[74:73],
                             6'd0,verify_data[72:71],1'b0,verify_data[70:64],verify_data[63:0]};
                    crc_byte<=0;state<=READBACK_CRC;
                end
                READBACK_CHECK:begin
                    if((crc_value^32'hffffffff)!=crc_expected)fail(4);
                    else begin
                        // ceil(duration/480), shared serial divider, DSP=0.
                        dividend<=total+32'd479;quotient<=0;remainder<=0;divide_bit<=0;state<=DIVIDE;
                    end
                end
                STORE:begin
                    write_address<=candidate[10:0]+received[10:0];write_enable<=1;
                    // CHECK already proved onset+length<=total<=28800000.
                    // Make the resulting seven zero bits explicit so the
                    // writable bank keeps the same range propagation as ROM.
                    write_data<={record[111:96],5'd0,record[81:80],lane,record[70:64],
                                 7'd0,length[24:0],7'd0,onset[24:0]};
                    last_onset<=onset;lane_seen[lane]<=1;lane_end[lane]<=end_time[31:0];lane_last[lane]<=onset;
                    lane_history[{lane,lane_pointer[lane]}]<=onset;lane_pointer[lane]<=lane_pointer[lane]+1'b1;
                    if(lane_count[lane]<8)lane_count[lane]<=lane_count[lane]+1'b1;
                    received<=received+1'b1;state<=RECEIVE;reply(0);
                end
                DIVIDE:begin
                    dividend<={dividend[30:0],1'b0};quotient<=next_quotient;
                    remainder<=subtract ? trial-11'd480 : trial[9:0];
                    if(divide_bit==31)begin
                        // Successful allocation bounds count<=1345; the
                        // accepted duration gives ceil(total/480)<=60000.
                        commit_descriptor<={7'd0,song_timbre,7'd0,total[24:0],1'b0,count[10:0],
                                            candidate[10:0],16'd0,next_quotient[15:0]};state<=PUBLISH;
                    end else divide_bit<=divide_bit+1'b1;
                end
                PUBLISH:if(commit_ready)begin
                    for(i=0;i<5;i=i+1)if(commit_slot==i)overlay_data[i*96+:96]<=commit_descriptor;
                    overlay_valid[commit_slot]<=1;session<=0;state<=IDLE;reply(0);
                end
                default:fail(9);
            endcase
        end
    end
endmodule
