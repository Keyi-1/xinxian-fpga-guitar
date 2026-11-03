`include "guitar_config.vh"

module sample_tick_gen #(
    parameter integer DIVISOR = `AUDIO_SAMPLE_DIV
) (
    input  wire clk_audio_ref,
    input  wire rst_n,
    output reg  sample_tick
);

    reg [7:0] div_count;

    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            div_count   <= 8'd0;
            sample_tick <= 1'b0;
        end
        else if (div_count == DIVISOR - 1) begin
            div_count   <= 8'd0;
            sample_tick <= 1'b1;
        end
        else begin
            div_count   <= div_count + 1'b1;
            sample_tick <= 1'b0;
        end
    end

endmodule