// Passive, coherent PCM mailbox. No backpressure reaches the audio path.
module guitar_pcm_cdc(input wire src_clk,src_rst_n,src_valid,
    input wire signed [23:0] src_pcm,input wire dst_clk,dst_rst_n,
    output reg dst_valid,output reg signed [23:0] dst_pcm,output reg overrun);
    reg [23:0] held;
    reg request,acknowledge;
    reg [1:0] ack_sync,request_sync;
    reg settling;
    always @(posedge src_clk) begin
        if(!src_rst_n)begin held<=0;request<=0;ack_sync<=0;overrun<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(src_valid)begin
                if(request==ack_sync[1])begin held<=src_pcm;request<=~request;end
                else overrun<=1;
            end
        end
    end
    always @(posedge dst_clk) begin
        if(!dst_rst_n)begin request_sync<=0;acknowledge<=0;settling<=0;dst_valid<=0;dst_pcm<=0;end
        else begin
            request_sync<={request_sync[0],request};dst_valid<=0;
            if(settling)begin
                dst_pcm<=held;dst_valid<=1;acknowledge<=request_sync[1];settling<=0;
            end else if(request_sync[1]!=acknowledge)settling<=1;
        end
    end
endmodule
