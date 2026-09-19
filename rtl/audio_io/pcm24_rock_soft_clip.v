// Post-mix, velocity-controlled soft clipper for the rock timbre.
// timbre_blend is Q8: 0 is exact dry bypass and 256 is fully processed.
module pcm24_rock_soft_clip (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid_in,
    input  wire signed [23:0] pcm_in,
    input  wire [1:0]         drive_level,
    input  wire [8:0]         timbre_blend,

    output reg                sample_valid,
    output reg signed [23:0]  pcm_out
);

    localparam signed [33:0] PCM_MAX       = 34'sd8388607;
    localparam signed [33:0] PCM_MIN       = -34'sd8388608;
    localparam signed [33:0] KNEE_LEVEL    = 34'sd4194304;
    localparam signed [33:0] CLIP_INPUT_HI = 34'sd12582910;
    localparam signed [33:0] CLIP_INPUT_LO = -34'sd12582912;

    reg [9:0] drive_gain_q8;
    reg [9:0] dry_weight_q8;
    reg signed [33:0] driven_product;
    reg signed [33:0] driven_sample;
    reg signed [23:0] clipped_sample;
    reg signed [34:0] dry_product;
    reg signed [34:0] wet_product;
    reg signed [34:0] blended_sample;

    function signed [23:0] soft_clip;
        input signed [33:0] value;
        reg signed [33:0] compressed;
        begin
            if (value >= CLIP_INPUT_HI)
                soft_clip = 24'sh7fffff;
            else if (value <= CLIP_INPUT_LO)
                soft_clip = 24'sh800000;
            else if (value > KNEE_LEVEL) begin
                compressed = KNEE_LEVEL + ((value - KNEE_LEVEL) >>> 1);
                soft_clip = compressed[23:0];
            end
            else if (value < -KNEE_LEVEL) begin
                compressed = -KNEE_LEVEL + ((value + KNEE_LEVEL) >>> 1);
                soft_clip = compressed[23:0];
            end
            else
                soft_clip = value[23:0];
        end
    endfunction

    function signed [23:0] saturate_pcm24;
        input signed [34:0] value;
        begin
            if (value > PCM_MAX)
                saturate_pcm24 = 24'sh7fffff;
            else if (value < PCM_MIN)
                saturate_pcm24 = 24'sh800000;
            else
                saturate_pcm24 = value[23:0];
        end
    endfunction

    always @* begin
        case (drive_level)
            2'd0: drive_gain_q8 = 10'd256;
            2'd1: drive_gain_q8 = 10'd320;
            2'd2: drive_gain_q8 = 10'd384;
            default: drive_gain_q8 = 10'd512;
        endcase

        dry_weight_q8 = 10'd256 - {1'b0, timbre_blend};
        driven_product = $signed(pcm_in) * $signed({1'b0, drive_gain_q8});
        driven_sample = driven_product >>> 8;
        clipped_sample = soft_clip(driven_sample);
        dry_product = $signed(pcm_in) * $signed({1'b0, dry_weight_q8});
        wet_product = $signed(clipped_sample) *
                      $signed({1'b0, timbre_blend});
        blended_sample = (dry_product + wet_product) >>> 8;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            pcm_out <= 24'sd0;
        end
        else begin
            sample_valid <= sample_valid_in;
            if (sample_valid_in)
                pcm_out <= saturate_pcm24(blended_sample);
        end
    end

endmodule
