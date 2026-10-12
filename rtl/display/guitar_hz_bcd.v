// One shared double-dabble converter for all four labels: no division/DSP.
// 44 board clocks per snapshot, completed inside vertical blanking.
module guitar_hz_bcd(input wire clk,rst_n,input wire [43:0] hz,output reg [47:0] digits);
    reg [43:0] last_hz,latched;
    reg busy;
    reg [1:0] voice;
    reg [3:0] count;
    reg [10:0] binary;
    reg [11:0] decimal;
    reg [11:0] adjusted;
    wire [11:0] next_decimal={adjusted[10:0],binary[10]};
    integer i;
    always @* begin
        adjusted=decimal;
        for(i=0;i<3;i=i+1)
            if(decimal[i*4+:4]>=5) adjusted[i*4+:4]=decimal[i*4+:4]+4'd3;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            last_hz<=0;latched<=0;busy<=0;voice<=0;count<=0;binary<=0;decimal<=0;digits<=0;
        end else if(!busy) begin
            if(last_hz!=hz) begin
                last_hz<=hz;latched<=hz;busy<=1;voice<=0;count<=0;binary<=hz[10:0];decimal<=0;
            end
        end else begin
            binary<=binary<<1; decimal<=next_decimal;
            if(count==10) begin
                digits[voice*12+:12]<=next_decimal;
                if(voice==3) busy<=0;
                else begin
                    voice<=voice+1'b1;count<=0;decimal<=0;
                    binary<=latched[(voice+2'd1)*11+:11];
                end
            end else count<=count+1'b1;
        end
    end
endmodule
