`include "../config/guitar_config.vh"

// Exact legacy Q15 triangle modulation, one shared shift/add multiplier.
// Prepare all four voices in 44 clocks at depth380 (72 at full16-bit depth).
// No DSP and no change to the voice schedule.
// Inactive, sliding, restruck and invalidated voices use a combinational bypass.
module four_string_vibrato_serial #(
    parameter [31:0] LFO_PHASE_INC=`VIBRATO_LFO_PHASE_INC,
    parameter [15:0] DEPTH_Q15=`VIBRATO_DEPTH_Q15
)(input wire clk,rst_n,sample_tick,
  input wire [3:0] enable,
  input wire [127:0] base_phase_inc,
  output wire [127:0] phase_inc,
  output wire busy,output reg deadline_miss);
    function integer bits_needed;
        input integer maximum;
        integer value;
        begin
            value=maximum;bits_needed=0;
            while(value>0)begin bits_needed=bits_needed+1;value=value>>1;end
            if(bits_needed<1)bits_needed=1;
        end
    endfunction
    localparam COEFFICIENT_BITS=bits_needed(DEPTH_Q15);
    localparam PRODUCT_BITS=32+COEFFICIENT_BITS;
    localparam COUNT_BITS=bits_needed(COEFFICIENT_BITS-1);
    localparam [31:0] ZERO_CROSSING=32'h40000000;
    localparam IDLE=0,SELECT=1,MULTIPLY=3,COMMIT=4;
    reg [2:0] state;
    reg tick_delayed;
    reg [1:0] channel;
    reg [COUNT_BITS-1:0] bit_index;
    reg [3:0] job_valid,result_valid;
    wire [3:0] base_matches;
    reg [31:0] lfo_phase[0:3];
    reg [127:0] base_snapshot,result_phase;
    reg negative;
    reg [COEFFICIENT_BITS-1:0] multiplier;
    reg [PRODUCT_BITS-1:0] multiplicand,accumulator;
    wire [31:0] selected_lfo=lfo_phase[channel];
    wire signed [16:0] triangle=selected_lfo[31] ?
        17'sd32767-$signed({1'b0,selected_lfo[30:15]}) :
        -17'sd32768+$signed({1'b0,selected_lfo[30:15]});
    // Explicit constant shifts keep the coefficient calculation out of DSPs.
    function signed [33:0] scale_triangle;
        input signed [16:0] value;
        reg signed [33:0] extended;
        integer b;
        begin
            extended={{17{value[16]}},value};scale_triangle=0;
            if(DEPTH_Q15==16'd380)
                scale_triangle=(extended<<<8)+(extended<<<7)-(extended<<<2);
            else for(b=0;b<16;b=b+1)
                if(DEPTH_Q15[b])scale_triangle=scale_triangle+(extended<<<b);
        end
    endfunction
    wire signed [33:0] scaled_triangle=scale_triangle(triangle)>>>15;
    wire [PRODUCT_BITS-1:0] next_accumulator=accumulator+(multiplier[0] ? multiplicand : {PRODUCT_BITS{1'b0}});
    wire signed [COEFFICIENT_BITS:0] coefficient=scaled_triangle[COEFFICIENT_BITS:0];
    wire [COEFFICIENT_BITS:0] coefficient_magnitude=coefficient[COEFFICIENT_BITS] ? -coefficient : coefficient;
    // One carry chain computes base + floor(signed_product/32768).
    // For a negative product, ~quotient + !remainder is exactly -ceil(product/32768).
    // Pack carry-in into an extra low bit, avoiding three independent adders.
    wire [34:0] quotient={{(50-PRODUCT_BITS){1'b0}},accumulator[PRODUCT_BITS-1:15]};
    wire [34:0] signed_quotient=quotient^{35{negative}};
    wire [35:0] sum_with_carry={3'd0,base_snapshot[channel*32+:32],1'b1}+
        {signed_quotient,negative && !(|accumulator[14:0])};
    wire signed [34:0] adjusted=sum_with_carry[35:1];
    wire [31:0] saturated=adjusted<0 ? 32'd0 :
        adjusted>35'sd4294967295 ? 32'hffffffff : adjusted[31:0];
    assign busy=state!=IDLE;
    genvar g;
    generate for(g=0;g<4;g=g+1)begin:output_bypass
        assign base_matches[g]=base_phase_inc[g*32+:32]==base_snapshot[g*32+:32];
        assign phase_inc[g*32+:32]=enable[g] && result_valid[g] && !deadline_miss &&
            base_matches[g] ?
            result_phase[g*32+:32] : base_phase_inc[g*32+:32];
    end endgenerate
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;tick_delayed<=0;channel<=0;bit_index<=0;
            job_valid<=0;result_valid<=0;base_snapshot<=0;
            result_phase<=0;negative<=0;
            multiplier<=0;multiplicand<=0;accumulator<=0;deadline_miss<=0;
            for(i=0;i<4;i=i+1)lfo_phase[i]<=ZERO_CROSSING;
        end else begin
            tick_delayed<=sample_tick;
            for(i=0;i<4;i=i+1)begin
                if(!enable[i])lfo_phase[i]<=ZERO_CROSSING;
                else if(sample_tick)lfo_phase[i]<=lfo_phase[i]+LFO_PHASE_INC;
                if(!enable[i] || !base_matches[i])
                    result_valid[i]<=0;
                if(busy && (!enable[i] || !base_matches[i]))job_valid[i]<=0;
            end
            if(sample_tick && busy)deadline_miss<=1;
            if(tick_delayed)begin
                if(busy)deadline_miss<=1;
                else begin
                    base_snapshot<=base_phase_inc;job_valid<=enable;
                    channel<=0;state<=SELECT;
                end
            end
            case(state)
                SELECT:begin
                    negative<=coefficient[COEFFICIENT_BITS];
                    multiplier<=coefficient_magnitude[COEFFICIENT_BITS-1:0];
                    multiplicand<={{COEFFICIENT_BITS{1'b0}},base_snapshot[channel*32+:32]};
                    accumulator<=0;bit_index<=0;state<=MULTIPLY;
                end
                MULTIPLY:begin
                    accumulator<=next_accumulator;multiplicand<=multiplicand<<1;
                    multiplier<=multiplier>>1;
                    if(bit_index==COEFFICIENT_BITS-1)state<=COMMIT;
                    else bit_index<=bit_index+1'b1;
                end
                COMMIT:begin
                    if(job_valid[channel] && enable[channel] &&
                       base_matches[channel])begin
                        result_phase[channel*32+:32]<=saturated;
                        result_valid[channel]<=1;
                    end
                    if(channel==3)state<=IDLE;
                    else begin channel<=channel+1'b1;state<=SELECT;end
                end
                default:begin end
            endcase
        end
    end
endmodule
