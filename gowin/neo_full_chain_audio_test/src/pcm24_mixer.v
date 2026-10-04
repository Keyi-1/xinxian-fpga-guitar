module pcm24_mixer (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       sample_valid_in,
    input  wire signed [23:0]         pcm0,
    input  wire signed [23:0]         pcm1,
    input  wire signed [23:0]         pcm2,
    input  wire signed [23:0]         pcm3,

    output reg                        sample_valid,
    output reg signed [23:0]          pcm_out
);

    reg signed [25:0] mix_sum;
    reg signed [23:0] mix_clipped;

    always @* begin
        mix_sum = $signed({{2{pcm0[23]}}, pcm0}) +
                  $signed({{2{pcm1[23]}}, pcm1}) +
                  $signed({{2{pcm2[23]}}, pcm2}) +
                  $signed({{2{pcm3[23]}}, pcm3});

        if (mix_sum > 26'sd8388607)
            mix_clipped = 24'sh7fffff;
        else if (mix_sum < -26'sd8388608)
            mix_clipped = 24'sh800000;
        else
            mix_clipped = mix_sum[23:0];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            pcm_out      <= 24'sd0;
        end
        else begin
            sample_valid <= sample_valid_in;
            if (sample_valid_in)
                pcm_out <= mix_clipped;
        end
    end

endmodule
