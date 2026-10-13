// Procedural hammer: independent innovations excite three damped resonators.
// Only coefficients/scalars are constants; no PCM or sampled filter trajectory.
// The parent lends its modal DSP during LOAD / ENV_B of modes 0..3. This module
// contains no multiplier, audio ROM or additional sample-processing clocks.
module piano_hammer_model #(
    parameter [31:0] SEED=32'h6d2b79f5
) (
    input wire clk, rst_n, sample_ce, note_on,
    input wire [1:0] strike_profile, profile, band,
    input wire [16:0] age, frame_age,
    input wire frame_active, first_multiply, save_first, update_filter, capture_gain,
    input wire lowpass_ce,
    input wire [1:0] lowpass_stage,
    input wire signed [34:0] product,
    output wire signed [17:0] operand_a,
    output wire signed [16:0] operand_b,
    output reg signed [15:0] value
);
    `include "../config/piano_hammer_coeffs.vh"
    reg [31:0] random_state;
    reg signed [15:0] noise[0:2];
    reg signed [15:0] input_noise[0:2];
    reg signed [15:0] lp0[0:2],lp1[0:2],lp2[0:2],lp3[0:2];
    reg signed [17:0] y1[0:2], y2[0:2];
    reg signed [18:0] band_output[0:2];
    reg signed [34:0] first_product;
    reg [23:0] slow, fast;
    integer i;
    function [31:0] random_step;
        input [31:0] x;
        reg [31:0] a,b;
        begin a=x^(x<<13); b=a^(a>>17); random_step=b^(b<<5); end
    endfunction
    function signed [17:0] clip_state;
        input signed [35:0] x;
        begin
            if(x>36'sd131071)clip_state=18'sd131071;
            else if(x< -36'sd131072)clip_state=-18'sd131072;
            else clip_state=x[17:0];
        end
    endfunction
    function signed [15:0] lowpass;
        input signed [15:0] x,previous;
        reg signed [16:0] delta;
        begin
            delta=$signed({x[15],x})-$signed({previous[15],previous});
            lowpass=previous+(delta>>>2);
        end
    endfunction
    wire [31:0] random0=random_step(random_state);
    wire [31:0] random1=random_step(random0);
    wire [31:0] random2=random_step(random1);
    wire signed [15:0] raw_noise[0:2];
    assign raw_noise[0]=random0[31:16];
    assign raw_noise[1]=random1[31:16];
    assign raw_noise[2]=random2[31:16];
    wire signed [15:0] lowpass_input=lowpass_stage==3 ? lp2[band] :
        lowpass_stage==2 ? lp1[band] : lowpass_stage==1 ? lp0[band] : input_noise[band];
    wire signed [15:0] lowpass_previous=lowpass_stage==3 ? lp3[band] :
        lowpass_stage==2 ? lp2[band] : lowpass_stage==1 ? lp1[band] : lp0[band];
    wire signed [15:0] lowpass_result=lowpass(lowpass_input,lowpass_previous);
    wire enabled=frame_active && frame_age<2048;
    wire [23:0] slow_delta=(slow>>10)+(slow>>11)+(age>=1664 ? slow>>6 : 24'd0);
    wire [23:0] fast_delta=(fast>>5)+(fast>>6);
    wire [23:0] envelope=slow>fast ? slow-fast : 24'd0;
    wire signed [20:0] filter_sum=
        $signed({{2{band_output[0][18]}},band_output[0]})+
        $signed({{2{band_output[1][18]}},band_output[1]})+
        $signed({{2{band_output[2][18]}},band_output[2]});
    wire signed [35:0] filter_sum_wide={{15{filter_sum[20]}},filter_sum};
    wire signed [35:0] feedback=$signed({first_product[34],first_product})+
                                        $signed({product[34],product});
    wire signed [17:0] noise_wide={{2{noise[band][15]}},noise[band]};
    wire signed [17:0] excitation=noise_wide >>> hammer_noise_shift(profile,band);
    wire signed [35:0] next_wide=$signed({{18{excitation[17]}},excitation})-(feedback>>>14);
    wire signed [17:0] next_y=enabled ? clip_state(next_wide) : 18'sd0;
    wire signed [34:0] scaled=product>>>15;
    assign operand_a=band==3 ? clip_state(filter_sum_wide) : first_multiply ? y1[band] : y2[band];
    assign operand_b=band==3 ? $signed({2'd0,envelope[23:9]}) :
        first_multiply ? hammer_a1(profile,band) : hammer_a2(profile,band);
    always @(posedge clk) begin
        if(!rst_n)begin
            random_state<=SEED==0 ? 32'd1 : SEED;
            slow<=0;fast<=0;first_product<=0;value<=0;
            for(i=0;i<3;i=i+1)begin
                noise[i]<=0;input_noise[i]<=0;lp0[i]<=0;lp1[i]<=0;lp2[i]<=0;lp3[i]<=0;
                y1[i]<=0;y2[i]<=0;band_output[i]<=0;
            end
        end else begin
            if(sample_ce)begin
                // Advance even during silence; retriggers use fresh innovations.
                random_state<=random2;
                // Capture all innovations and the old final pole per sample.
                // The four LP updates run backward during the corresponding
                // mode's LOAD / ENV_B / INC / PHASE. Each reads its old lower
                // pole, exactly matching simultaneous updates, with one ALU.
                for(i=0;i<3;i=i+1)begin
                    input_noise[i]<=raw_noise[i];
                    noise[i]<=lp3[i];
                end
                if(note_on)begin
                    slow<=hammer_envelope_start(strike_profile);
                    fast<=hammer_envelope_start(strike_profile);
                    for(i=0;i<3;i=i+1)begin y1[i]<=0;y2[i]<=0;band_output[i]<=0;end
                end else begin slow<=slow-slow_delta;fast<=fast-fast_delta;end
            end
            if(lowpass_ce)begin
                case(lowpass_stage)
                    3: lp3[band]<=lowpass_result;
                    2: lp2[band]<=lowpass_result;
                    1: lp1[band]<=lowpass_result;
                    default: lp0[band]<=lowpass_result;
                endcase
            end
            if(save_first)first_product<=product;
            if(update_filter)begin
                y2[band]<=y1[band];y1[band]<=next_y;
                // Bandpass numerator (1-z^-2) rejects DC and Nyquist noise.
                band_output[band]<=enabled ?
                    $signed({next_y[17],next_y})-$signed({y2[band][17],y2[band]}) : 19'sd0;
            end
            if(capture_gain)begin
                if(!enabled)value<=0;
                else if(scaled>35'sd2048)value<=16'sd2048;
                else if(scaled< -35'sd2048)value<=-16'sd2048;
                else value<=scaled[15:0];
            end
        end
    end
endmodule
