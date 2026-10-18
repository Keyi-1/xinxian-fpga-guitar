// Hold complete events through a request/ack CDC. While busy retain only the
// newest pending pose; never synchronize enum bits independently.
module posture_timbre_cdc(
    input wire src_clk,src_rst_n,src_event,input wire [1:0] src_timbre,
    input wire dst_clk,dst_rst_n,output wire dst_event,output wire [1:0] dst_timbre);
    reg queued,send;
    reg [1:0] latest,held_send;
    wire busy,done,valid;
    mode_command_cdc #(.WIDTH(2)) bridge(.src_clk(src_clk),.src_rst_n(src_rst_n),
        .src_send(send),.src_mode(held_send),.src_busy(busy),.src_done(done),
        .dst_clk(dst_clk),.dst_rst_n(dst_rst_n),.dst_valid(valid),.dst_mode(dst_timbre),.dst_ack(valid));
    // mode_command_cdc holds valid through one acknowledge edge. Consumers
    // see this once (the acknowledge is unconditional and same-domain).
    assign dst_event=valid;
    always @(posedge src_clk)begin
        if(!src_rst_n)begin queued<=0;send<=0;latest<=0;held_send<=0;end
        else begin
            send<=0;
            if(src_event)begin latest<=src_timbre;queued<=1;end
            if(queued && !busy && !send)begin
                held_send<=src_event ? src_timbre : latest;send<=1;queued<=0;
            end
        end
    end
endmodule
