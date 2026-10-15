// Hold command data until its destination explicitly acknowledges execution.
module mode_command_cdc #(parameter integer WIDTH=2)(input wire src_clk,src_rst_n,src_send,
    input wire [WIDTH-1:0] src_mode,output reg src_busy,src_done,
    input wire dst_clk,dst_rst_n,output reg dst_valid,
    output reg [WIDTH-1:0] dst_mode,input wire dst_ack);
    reg request,ack;
    reg [WIDTH-1:0] held;
    reg [1:0] request_sync,ack_sync;
    reg settling;
    always @(posedge src_clk)begin
        if(!src_rst_n)begin request<=0;held<=0;ack_sync<=0;src_busy<=0;src_done<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};src_done<=0;
            if(src_send && !src_busy)begin held<=src_mode;request<=~request;src_busy<=1;end
            if(src_busy && ack_sync[1]==request)begin src_busy<=0;src_done<=1;end
        end
    end
    always @(posedge dst_clk)begin
        if(!dst_rst_n)begin ack<=0;request_sync<=0;dst_valid<=0;dst_mode<=0;settling<=0;end
        else begin
            request_sync<={request_sync[0],request};
            if(request_sync[1]!=ack && !dst_valid)begin
                if(!settling)settling<=1;
                else begin dst_mode<=held;dst_valid<=1;settling<=0;end
            end
            if(dst_valid && dst_ack)begin dst_valid<=0;ack<=request_sync[1];end
        end
    end
endmodule
