module test_tone_trigger #(
    parameter integer START_DELAY_CYCLES = 128,
    parameter integer HOLD_CYCLES        = 128
) (
    input  wire clk,
    input  wire rst_n,
    output reg  note_on
);

    reg [31:0] count;

    always @(posedge clk) begin
        if (!rst_n) begin
            count   <= 32'd0;
            note_on <= 1'b0;
        end
        else if (count < START_DELAY_CYCLES) begin
            count   <= count + 1'b1;
            note_on <= 1'b0;
        end
        else if (count < START_DELAY_CYCLES + HOLD_CYCLES) begin
            count   <= count + 1'b1;
            note_on <= 1'b1;
        end
        else begin
            note_on <= 1'b0;
        end
    end

endmodule