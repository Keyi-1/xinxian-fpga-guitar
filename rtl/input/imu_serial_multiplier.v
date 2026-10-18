// One unsigned shift/add multiplier. 36 clocks, no DSP primitive or '*' RTL.
module imu_serial_multiplier(
    input wire clk,rst_n,start,input wire [35:0] a,b,
    output reg busy,done,output reg [71:0] product);
    reg [71:0] shifted,accumulator;
    reg [35:0] multiplier;
    reg [5:0] count;
    wire [71:0] next_sum=accumulator+(multiplier[0] ? shifted : 72'd0);
    always @(posedge clk)begin
        if(!rst_n)begin busy<=0;done<=0;product<=0;shifted<=0;accumulator<=0;multiplier<=0;count<=0;end
        else begin
            done<=0;
            if(start && !busy)begin
                shifted<={36'd0,a};multiplier<=b;accumulator<=0;count<=0;busy<=1;
            end else if(busy)begin
                accumulator<=next_sum;shifted<=shifted<<1;multiplier<=multiplier>>1;
                if(count==35)begin product<=next_sum;busy<=0;done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule
