// Standard I2S: WS=0 left, WS=1 right, 32 BCLK periods per channel.
// With a 12.288 MHz reference, REF_DIV=2 gives 3.072 MHz BCLK / 48 kHz WS.
// SD and WS change only on falling BCLK; the receiver samples rising BCLK.
module i2s_tx #(
    parameter integer REF_DIV = 2
) (
    input wire clk_audio_ref, rst_n,
    input wire sample_valid,
    input wire [15:0] sample_left, sample_right,
    output reg i2s_bclk, i2s_ws, i2s_data
);
    localparam integer DIV_BITS = REF_DIV > 1 ? $clog2(REF_DIV) : 1;
    reg [DIV_BITS-1:0] ref_count;
    reg [5:0] bit_count;
    reg [31:0] shift_reg;
    reg [15:0] current_left, current_right;
    reg [15:0] pending_left, pending_right;
    reg pending_valid;

    // One stereo sample per 128*REF_DIV reference clocks. The pending pair
    // is committed atomically at the right-to-left WS transition, at the same
    // reference-clock edge as PT8211's frame boundary (PT REF_DIV=2*this).
    // A boundary-coincident valid takes priority. Missing input repeats the
    // last pair, matching PT8211; this is not a FIFO for faster sample sources.
    always @(posedge clk_audio_ref) begin
        if (!rst_n) begin
            ref_count <= 0; bit_count <= 0; shift_reg <= 0;
            current_left <= 0; current_right <= 0;
            pending_left <= 0; pending_right <= 0; pending_valid <= 0;
            i2s_bclk <= 0; i2s_ws <= 0; i2s_data <= 0;
        end else begin
            if (sample_valid) begin
                pending_left <= sample_left; pending_right <= sample_right;
                pending_valid <= 1;
            end
            if (ref_count == REF_DIV-1) begin
                ref_count <= 0;
                i2s_bclk <= ~i2s_bclk;
                if (i2s_bclk) begin
                    bit_count <= bit_count + 1'b1;
                    i2s_data <= shift_reg[31];
                    shift_reg <= {shift_reg[30:0],1'b0};
                    if (bit_count == 31) begin
                        // This bit is the final LEFT padding bit. RIGHT MSB
                        // follows on the next falling BCLK, one bit later.
                        i2s_ws <= 1;
                        shift_reg <= {current_right,16'd0};
                    end else if (bit_count == 63) begin
                        // Final RIGHT padding bit; LEFT MSB follows one bit
                        // later. Both channels switch to the same new pair.
                        i2s_ws <= 0;
                        i2s_data <= 0;
                        pending_valid <= 0;
                        if (sample_valid) begin
                            current_left <= sample_left; current_right <= sample_right;
                            shift_reg <= {sample_left,16'd0};
                        end else if (pending_valid) begin
                            current_left <= pending_left; current_right <= pending_right;
                            shift_reg <= {pending_left,16'd0};
                        end else begin
                            shift_reg <= {current_left,16'd0};
                        end
                    end
                end
            end else ref_count <= ref_count + 1'b1;
        end
    end
endmodule
