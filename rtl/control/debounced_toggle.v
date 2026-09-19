// Active-low mechanical button conditioner.
// A qualified press toggles the state exactly once; release only rearms it.
module debounced_toggle #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire button_n,
    output reg  toggle_state,
    output reg  pressed_pulse
);

    reg button_sync1;
    reg button_sync2;
    reg stable_button_n;
    reg [31:0] debounce_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            button_sync1 <= 1'b1;
            button_sync2 <= 1'b1;
        end
        else begin
            button_sync1 <= button_n;
            button_sync2 <= button_sync1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            stable_button_n <= 1'b1;
            debounce_count  <= 32'd0;
            toggle_state    <= 1'b0;
            pressed_pulse   <= 1'b0;
        end
        else begin
            pressed_pulse <= 1'b0;

            if (button_sync2 == stable_button_n) begin
                debounce_count <= 32'd0;
            end
            else if ((DEBOUNCE_CYCLES <= 1) ||
                     (debounce_count >= DEBOUNCE_CYCLES - 1)) begin
                stable_button_n <= button_sync2;
                debounce_count  <= 32'd0;

                if (!button_sync2) begin
                    toggle_state  <= ~toggle_state;
                    pressed_pulse <= 1'b1;
                end
            end
            else begin
                debounce_count <= debounce_count + 1'b1;
            end
        end
    end

endmodule
