// Delivered 480x272 panel timing and direct spectrum rendering. No full
// framebuffer is used: each active pixel is generated from one of 32 bars.
module rgb_spectrum_timing #(
    parameter integer H_ACTIVE = 480,
    parameter integer H_FRONT  = 8,
    parameter integer H_SYNC   = 4,
    parameter integer H_BACK   = 39,
    parameter integer V_ACTIVE = 272,
    parameter integer V_FRONT  = 8,
    parameter integer V_SYNC   = 4,
    parameter integer V_BACK   = 8,
    parameter integer BAR_SLOT = 15,
    parameter integer BAR_WIDTH = 12
) (
    input  wire       pixel_clk,
    input  wire       rst_n,
    output wire [4:0] bar_read_index,
    input  wire [8:0] bar_height,
    input  wire [8:0] peak_height,

    output wire       lcd_hsync,
    output wire       lcd_vsync,
    output wire       lcd_de,
    output reg [7:0]  lcd_r,
    output reg [7:0]  lcd_g,
    output reg [7:0]  lcd_b,
    output wire       frame_start,
    output wire [10:0] pixel_x,
    output wire [9:0]  pixel_y
);

    localparam integer H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    reg [10:0] h_count;
    reg [9:0] v_count;
    reg [10:0] local_x;
    reg [9:0] height_from_bottom;

    assign lcd_de = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign lcd_hsync = ~((h_count >= H_ACTIVE + H_FRONT) &&
                         (h_count < H_ACTIVE + H_FRONT + H_SYNC));
    assign lcd_vsync = ~((v_count >= V_ACTIVE + V_FRONT) &&
                         (v_count < V_ACTIVE + V_FRONT + V_SYNC));
    assign frame_start = (h_count == 0) && (v_count == 0);
    assign pixel_x = h_count;
    assign pixel_y = v_count;
    assign bar_read_index = (h_count < H_ACTIVE) ?
                            (h_count / BAR_SLOT) : 5'd0;

    always @* begin
        local_x = h_count % BAR_SLOT;
        height_from_bottom = V_ACTIVE - 1 - v_count;
        lcd_r = 8'h00;
        lcd_g = 8'h00;
        lcd_b = 8'h00;
        if (lcd_de && (bar_read_index < 32) &&
            (local_x < BAR_WIDTH)) begin
            if (height_from_bottom < bar_height) begin
                lcd_r = 8'h00;
                lcd_g = 8'hc0;
                lcd_b = 8'hff;
            end
            else if ((peak_height != 0) &&
                     ((height_from_bottom == peak_height) ||
                      (height_from_bottom + 1'b1 == peak_height))) begin
                lcd_r = 8'hff;
                lcd_g = 8'hd0;
                lcd_b = 8'h20;
            end
        end
    end

    always @(posedge pixel_clk) begin
        if (!rst_n) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end
        else if (h_count == H_TOTAL - 1) begin
            h_count <= 11'd0;
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 1'b1;
        end
        else
            h_count <= h_count + 1'b1;
    end

endmodule
