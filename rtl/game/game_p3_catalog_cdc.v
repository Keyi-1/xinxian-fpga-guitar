// A held descriptor crosses once per acknowledged request. No data bits are
// independently synchronized. Source must hold valid/slot/descriptor until
// ready, then drop valid before another publication. Both domains share reset.
module game_p3_catalog_cdc(
    input wire src_clk,src_rst_n,valid,input wire [2:0] slot,
    input wire [95:0] descriptor,output wire ready,
    input wire dst_clk,dst_rst_n,
    output reg [4:0] overlay_valid,output reg [479:0] overlay_data);
    reg request,seen,acknowledge;
    reg ack_meta,ack_sync,req_meta,req_sync;
    reg [2:0] held_slot;
    reg [95:0] held_descriptor;
    assign ready=seen && ack_sync==request;
    always @(posedge src_clk)begin
        if(!src_rst_n)begin request<=0;seen<=0;ack_meta<=0;ack_sync<=0;held_slot<=0;held_descriptor<=0;end
        else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;
            if(!valid)seen<=0;
            else if(!seen)begin
                held_slot<=slot;held_descriptor<=descriptor;request<=~request;seen<=1;
            end
        end
    end
    integer i;
    always @(posedge dst_clk)begin
        if(!dst_rst_n)begin req_meta<=0;req_sync<=0;acknowledge<=0;overlay_valid<=0;overlay_data<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(req_sync!=acknowledge)begin
                for(i=0;i<5;i=i+1)if(held_slot==i)overlay_data[i*96+:96]<=held_descriptor;
                if(held_slot<5)overlay_valid[held_slot]<=1;
                acknowledge<=req_sync;
            end
        end
    end
endmodule
