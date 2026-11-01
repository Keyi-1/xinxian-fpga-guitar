// Held-payload/toggle mailbox: audio sample requests -> fast KS computation ->
// coherent four-voice result. Only toggles cross synchronizers; payloads remain
// unchanged until acknowledged. Two KS lanes service 32 independent contexts.
module ks_tdm_bank(
    input wire audio_clk,audio_rst_n,compute_clk,compute_rst_n,start,
    input wire [3:0] strike,enabled,harmony,
    input wire sustain,
    input wire [127:0] increment,harmony_increment,
    output reg [111:0] value,
    output wire busy,
    output reg overrun
);
    reg [268:0] request_payload;
    reg request_toggle;
    reg done_toggle;
    reg done_meta,done_sync,done_seen;
    reg request_meta,request_sync,request_seen;
    reg [111:0] result_payload;
    reg [1:0] voice_index;
    reg running,launch;
    wire kernel_busy;
    wire signed [27:0] kernel_value;
    assign busy=request_toggle!=done_sync;
    always @(posedge audio_clk or negedge audio_rst_n)begin
        if(!audio_rst_n)begin
            request_payload<=0;request_toggle<=0;done_meta<=0;done_sync<=0;
            done_seen<=0;value<=0;overrun<=0;
        end else begin
            done_meta<=done_toggle;done_sync<=done_meta;
            if(done_sync!=done_seen)begin value<=result_payload;done_seen<=done_sync;end
            if(start)begin
                if(busy)overrun<=1;
                else begin
                    request_payload<={sustain,harmony,enabled,strike,harmony_increment,increment};
                    request_toggle<=~request_toggle;
                end
            end
        end
    end
    always @(posedge compute_clk or negedge compute_rst_n)begin
        if(!compute_rst_n)begin
            request_meta<=0;request_sync<=0;request_seen<=0;done_toggle<=0;
            result_payload<=0;voice_index<=0;running<=0;launch<=0;
        end else begin
            request_meta<=request_toggle;request_sync<=request_meta;launch<=0;
            if(!running && !kernel_busy && request_sync!=request_seen)begin
                // The audio producer holds this bus until done is synchronized
                // back. All four contexts therefore consume the same stable bus;
                // a second 269-bit copy in this domain is unnecessary.
                request_seen<=request_sync;
                voice_index<=0;running<=1;launch<=1;
            end else if(running && !launch && !kernel_busy)begin
                result_payload[voice_index*28+:28]<=kernel_value;
                if(voice_index==3)begin running<=0;done_toggle<=request_seen;end
                else begin voice_index<=voice_index+1'b1;launch<=1;end
            end
        end
    end
    karplus_strong_voice #(.CONTEXTS(4)) kernel(
        .clk(compute_clk),.rst_n(compute_rst_n),.start(launch),.context_index(voice_index),
        .strike(request_payload[256+voice_index]),.enabled(request_payload[260+voice_index]),
        .harmony(request_payload[264+voice_index]),.sustain(request_payload[268]),
        .increment(request_payload[voice_index*32+:32]),
        .harmony_increment(request_payload[128+voice_index*32+:32]),
        .value(kernel_value),.busy(kernel_busy));
endmodule
