`include "guitar_config.vh"

// Shared click-free timbre interpolation control.
// blend=0 selects the classic harmonic profile; blend=256 selects rock.
module timbre_blend_smoother #(
    parameter integer BLEND_SAMPLES = `TIMBRE_BLEND_SAMPLES
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sample_ce,
    input  wire       timbre_select,
    output reg [8:0]  blend,
    output wire       busy
);

    localparam integer BLEND_MAX = 256;
    localparam integer BLEND_STEP =
        (BLEND_MAX + BLEND_SAMPLES - 1) / BLEND_SAMPLES;

    assign busy = timbre_select ? (blend < BLEND_MAX) : (blend != 0);

    always @(posedge clk) begin
        if (!rst_n) begin
            blend <= 9'd0;
        end
        else if (sample_ce) begin
            if (timbre_select) begin
                if (blend + BLEND_STEP >= BLEND_MAX)
                    blend <= BLEND_MAX;
                else
                    blend <= blend + BLEND_STEP;
            end
            else begin
                if (blend <= BLEND_STEP)
                    blend <= 9'd0;
                else
                    blend <= blend - BLEND_STEP;
            end
        end
    end

endmodule
