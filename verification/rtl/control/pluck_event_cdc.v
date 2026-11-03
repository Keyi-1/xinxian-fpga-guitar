// Transfers one-shot per-string pluck events from the system to audio clock.
module pluck_event_cdc (
    input  wire       src_clk,
    input  wire       src_rst_n,
    input  wire [3:0] src_event,
    input  wire [7:0] src_velocity_level,

    input  wire       dst_clk,
    input  wire       dst_rst_n,
    output reg  [3:0] dst_event,
    output reg  [7:0] dst_velocity_level
);

    reg [3:0] event_toggle_src;
    reg [3:0] event_toggle_sync1;
    reg [3:0] event_toggle_sync2;
    reg [3:0] event_toggle_seen;
    reg [7:0] velocity_sync1;
    reg [7:0] velocity_sync2;

    always @(posedge src_clk) begin
        if (!src_rst_n)
            event_toggle_src <= 4'd0;
        else
            event_toggle_src <= event_toggle_src ^ src_event;
    end

    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            event_toggle_sync1 <= 4'd0;
            event_toggle_sync2 <= 4'd0;
            event_toggle_seen  <= 4'd0;
            dst_event          <= 4'd0;
            velocity_sync1     <= 8'd0;
            velocity_sync2     <= 8'd0;
            dst_velocity_level <= 8'd0;
        end
        else begin
            event_toggle_sync1 <= event_toggle_src;
            event_toggle_sync2 <= event_toggle_sync1;
            velocity_sync1     <= src_velocity_level;
            velocity_sync2     <= velocity_sync1;
            dst_event          <= event_toggle_sync2 ^ event_toggle_seen;
            event_toggle_seen  <= event_toggle_sync2;
            if (event_toggle_sync2 != event_toggle_seen)
                dst_velocity_level <= velocity_sync2;
        end
    end

endmodule
