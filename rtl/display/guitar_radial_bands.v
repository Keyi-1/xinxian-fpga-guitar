// 32 real FFT bands, displayed as 64 interpolated radial bars. No empty
// band assignments at low frequencies; DC excluded, Nyquist included.
module guitar_radial_bands(input wire clk,rst_n,bin_valid,frame_done,
    input wire [9:0] bin_index,input wire [18:0] bin_magnitude,
    output reg [159:0] targets,output reg update);
    reg [18:0] work [0:31];
    reg [159:0] pending_targets;
    reg [18:0] maximum,reference,agc;
    reg [4:0] index;
    reg reducing;
    function [4:0] map;
        input [9:0] b;
        begin
            if(b<15)map=b==0 ? 0 : b-1'b1;
            else if(b<19)map=14;else if(b<23)map=15;else if(b<27)map=16;
            else if(b<33)map=17;else if(b<41)map=18;else if(b<49)map=19;
            else if(b<60)map=20;else if(b<73)map=21;else if(b<89)map=22;
            else if(b<108)map=23;else if(b<131)map=24;else if(b<159)map=25;
            else if(b<193)map=26;else if(b<235)map=27;else if(b<285)map=28;
            else if(b<347)map=29;else if(b<421)map=30;else map=31;
        end
    endfunction
    function [7:0] log2q3;
        input [18:0] v;
        integer k;
        reg [4:0] exponent;
        reg [18:0] normalized;
        begin
            exponent=0;
            for(k=0;k<19;k=k+1)if(v[k])exponent=k;
            normalized=exponent>=3 ? v>>(exponent-3) : v<<(3-exponent);
            log2q3={exponent,3'd0}+{5'd0,normalized[2:0]};
        end
    endfunction
    wire [18:0] incoming_max=bin_valid && bin_index!=0 && bin_magnitude>maximum ? bin_magnitude : maximum;
    wire [18:0] decayed=agc-(agc>>4);
    wire [18:0] next_ref=incoming_max>decayed ? incoming_max : decayed;
    wire [7:0] lr=log2q3(reference),lv=log2q3(work[index]);
    wire [7:0] difference=lr>lv ? lr-lv : 8'd0;
    wire [9:0] attenuation={2'd0,difference}+({2'd0,difference}<<1);
    wire [4:0] height=work[index]<8 || maximum<32 ? 5'd0 :
        attenuation[9:3]>=27 ? 5'd0 : 5'd27-attenuation[7:3];
    // maximum is retained during reduction, then cleared with the last band.
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            maximum<=0;reference<=1024;agc<=1024;index<=0;reducing<=0;update<=0;targets<=0;pending_targets<=0;
            for(i=0;i<32;i=i+1)work[i]<=0;
        end else begin
            update<=0;
            if(bin_valid && bin_index!=0)begin
                if(bin_magnitude>work[map(bin_index)])work[map(bin_index)]<=bin_magnitude;
                if(bin_magnitude>maximum)maximum<=bin_magnitude;
            end
            if(frame_done)begin
                reference<=next_ref<1024 ? 19'd1024 : next_ref;
                agc<=next_ref<1024 ? 19'd1024 : next_ref;
                maximum<=incoming_max;index<=0;reducing<=1;
            end else if(reducing)begin
                pending_targets[index*5+:5]<=height;work[index]<=0;
                if(index==31)begin
                    targets<=pending_targets;targets[155+:5]<=height;
                    reducing<=0;update<=1;maximum<=0;
                end
                else index<=index+1'b1;
            end
        end
    end
endmodule
