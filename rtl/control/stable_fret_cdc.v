// Transfers a stable fret update from the scan clock to the audio clock.
// The source must not issue another update before the destination has had
// two audio clocks to observe this one. The 1 kHz scanner rate satisfies it.
module stable_fret_cdc (
    input  wire        src_clk,
    input  wire        src_rst_n,
    input  wire        src_valid,
    input  wire [15:0] src_fret_id,

    input  wire        dst_clk,
    input  wire        dst_rst_n,
    output reg         dst_valid,
    output reg  [15:0] dst_fret_id
);

    reg [15:0] fret_id_src;
    reg        update_toggle_src;

    reg [15:0] fret_id_sync1;
    reg [15:0] fret_id_sync2;
    reg        update_toggle_sync1;
    reg        update_toggle_sync2;
    reg        update_toggle_seen;

    always @(posedge src_clk) begin
        if (!src_rst_n) begin
            fret_id_src      <= 16'd0;
            update_toggle_src <= 1'b0;
        end
        else if (src_valid) begin
            fret_id_src       <= src_fret_id;
            update_toggle_src <= ~update_toggle_src;
        end
    end

    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            fret_id_sync1       <= 16'd0;
            fret_id_sync2       <= 16'd0;
            update_toggle_sync1 <= 1'b0;
            update_toggle_sync2 <= 1'b0;
            update_toggle_seen  <= 1'b0;
            dst_valid           <= 1'b0;
            dst_fret_id         <= 16'd0;
        end
        else begin
            fret_id_sync1       <= fret_id_src;
            fret_id_sync2       <= fret_id_sync1;
            update_toggle_sync1 <= update_toggle_src;
            update_toggle_sync2 <= update_toggle_sync1;
            dst_valid           <= 1'b0;

            if (update_toggle_sync2 != update_toggle_seen) begin
                update_toggle_seen <= update_toggle_sync2;
                dst_fret_id        <= fret_id_sync2;
                dst_valid          <= 1'b1;
            end
        end
    end

endmodule
