module game_snapshot_cdc(input wire src_clk,src_rst_n,input wire [255:0] src_snapshot,
    input wire dst_clk,dst_rst_n,dst_request,output reg [255:0] dst_snapshot,output reg dst_update);
    reg request,ack,busy,settling;
    reg [1:0] request_sync,ack_sync;
    reg [255:0] held;
    always @(posedge src_clk)begin
        if(!src_rst_n)begin request_sync<=0;ack<=0;held<=0;end
        else begin request_sync<={request_sync[0],request};
            if(request_sync[1]!=ack)begin held<=src_snapshot;ack<=request_sync[1];end
        end
    end
    always @(posedge dst_clk)begin
        if(!dst_rst_n)begin request<=0;ack_sync<=0;busy<=0;settling<=0;dst_snapshot<=0;dst_update<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};dst_update<=0;
            if(dst_request && !busy)begin request<=~request;busy<=1;end
            if(busy && ack_sync[1]==request)begin
                if(!settling)settling<=1;
                else begin dst_snapshot<=held;dst_update<=1;busy<=0;settling<=0;end
            end
        end
    end
endmodule
