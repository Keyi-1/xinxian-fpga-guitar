// Coherent 32-bar snapshot transfer from the audio clock to the pixel clock.
// The source shadow bank remains stable until the destination acknowledges the
// request toggle, making the multi-bit transfer safe without a framebuffer.
module spectrum_bar_cdc (
    input  wire       src_clk,
    input  wire       src_rst_n,
    input  wire       src_frame_update,
    output wire [4:0] src_read_index,
    input  wire [8:0] src_bar_height,
    input  wire [8:0] src_peak_height,
    output reg        src_overrun,

    input  wire       dst_clk,
    input  wire       dst_rst_n,
    input  wire [4:0] dst_read_index,
    output wire [8:0] dst_bar_height,
    output wire [8:0] dst_peak_height,
    output reg        dst_frame_update
);

    reg [8:0] shadow_bar [0:31];
    reg [8:0] shadow_peak [0:31];
    reg [8:0] display_bar [0:31];
    reg [8:0] display_peak [0:31];
    reg [4:0] copy_index;
    reg copying;
    reg request_toggle;
    reg acknowledge_toggle;
    reg acknowledge_sync1;
    reg acknowledge_sync2;
    reg request_sync1;
    reg request_sync2;
    integer i;

    assign src_read_index = copy_index;
    assign dst_bar_height = display_bar[dst_read_index];
    assign dst_peak_height = display_peak[dst_read_index];

    always @(posedge src_clk) begin
        if (!src_rst_n) begin
            copy_index <= 5'd0;
            copying <= 1'b0;
            request_toggle <= 1'b0;
            acknowledge_sync1 <= 1'b0;
            acknowledge_sync2 <= 1'b0;
            src_overrun <= 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                shadow_bar[i] <= 9'd0;
                shadow_peak[i] <= 9'd0;
            end
        end
        else begin
            acknowledge_sync1 <= acknowledge_toggle;
            acknowledge_sync2 <= acknowledge_sync1;
            if (src_frame_update) begin
                if (!copying && (request_toggle == acknowledge_sync2)) begin
                    copying <= 1'b1;
                    copy_index <= 5'd0;
                end
                else
                    src_overrun <= 1'b1;
            end
            if (copying) begin
                shadow_bar[copy_index] <= src_bar_height;
                shadow_peak[copy_index] <= src_peak_height;
                if (copy_index == 5'd31) begin
                    copying <= 1'b0;
                    request_toggle <= ~request_toggle;
                end
                else
                    copy_index <= copy_index + 1'b1;
            end
        end
    end

    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            request_sync1 <= 1'b0;
            request_sync2 <= 1'b0;
            acknowledge_toggle <= 1'b0;
            dst_frame_update <= 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                display_bar[i] <= 9'd0;
                display_peak[i] <= 9'd0;
            end
        end
        else begin
            request_sync1 <= request_toggle;
            request_sync2 <= request_sync1;
            dst_frame_update <= 1'b0;
            if (request_sync2 != acknowledge_toggle) begin
                for (i = 0; i < 32; i = i + 1) begin
                    display_bar[i] <= shadow_bar[i];
                    display_peak[i] <= shadow_peak[i];
                end
                acknowledge_toggle <= request_sync2;
                dst_frame_update <= 1'b1;
            end
        end
    end

endmodule
