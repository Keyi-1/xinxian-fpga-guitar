// Destination-requested bundled-data mailbox. The source holds all 400 bits
// until the next request. Ack is synchronized, then one more settling clock
// precedes the atomic destination capture. Requests never stall the audio.
module guitar_visual_cdc(
    input wire src_clk,src_rst_n,
    input wire [399:0] src_snapshot,
    input wire dst_clk,dst_rst_n,dst_request,
    output reg [399:0] dst_snapshot,
    output reg dst_update
);
    reg request_toggle,ack_toggle;
    reg [1:0] request_sync,ack_sync;
    reg [399:0] held_snapshot;
    reg busy,settling;
    always @(posedge src_clk) begin
        if(!src_rst_n) begin request_sync<=0; ack_toggle<=0; held_snapshot<=0; end
        else begin
            request_sync<={request_sync[0],request_toggle};
            if(request_sync[1]!=ack_toggle) begin
                held_snapshot<=src_snapshot;
                ack_toggle<=request_sync[1];
            end
        end
    end
    always @(posedge dst_clk) begin
        if(!dst_rst_n) begin
            request_toggle<=0; ack_sync<=0; dst_snapshot<=0;
            dst_update<=0; busy<=0; settling<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};
            dst_update<=0;
            if(dst_request && !busy) begin request_toggle<=~request_toggle; busy<=1; end
            if(busy && ack_sync[1]==request_toggle) begin
                if(!settling) settling<=1;
                else begin dst_snapshot<=held_snapshot; dst_update<=1; busy<=0; settling<=0; end
            end
        end
    end
endmodule
