// Verified Tang Mega 60K + NEO Dock 31005 panel timing, 50 MHz / 6.
// All logic remains in the board-clock domain. RGB is sampled here at the
// falling DCLK edge, giving the panel 60 ns before its next rising edge.
module lcd_rgb_scan_480x272 #(parameter integer ROTATE_180=0) (
    input wire clk,
    input wire rst_n,
    input wire [17:0] pixel_rgb,
    output wire [8:0] pixel_x,
    output reg [8:0] pixel_y,
    output wire pixel_active,
    output reg frame_start,
    output reg lcd_pclk,
    output reg lcd_hsync,
    output reg lcd_vsync,
    output reg lcd_de,
    output reg [5:0] lcd_r,
    output reg [5:0] lcd_g,
    output reg [5:0] lcd_b
);
    reg [2:0] phase;
    reg [9:0] h_count;
    reg [8:0] v_count;
    assign pixel_active = h_count >= 43 && h_count < 523
                       && v_count >= 12 && v_count < 284;
    // 479-(h-43) = 522-h (modulo 512): use one constant subtraction,
    // rather than putting two carry chains before the pixel renderers.
    assign pixel_x = ROTATE_180 ? 9'd10 - h_count[8:0] : h_count[8:0] - 9'd43;
    // Maintain the exact (v_count-12) modulo512 value alongside v_count.
    // This removes a carry chain before every UI y decode, without delaying
    // coordinates or changing the six-clock pixel/output schedule.
    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= 0;
            h_count <= 0;
            v_count <= 0;
            pixel_y <= ROTATE_180 ? 9'd283 : 9'd500;
            frame_start <= 0;
            lcd_pclk <= 0;
            lcd_hsync <= 1;
            lcd_vsync <= 1;
            lcd_de <= 0;
            lcd_r <= 0;
            lcd_g <= 0;
            lcd_b <= 0;
        end else begin
            frame_start <= 0;
            if (phase == 2) lcd_pclk <= 1;
            if (phase == 5) begin
                phase <= 0;
                lcd_pclk <= 0;
                lcd_hsync <= h_count >= 4;
                lcd_vsync <= v_count >= 4;
                lcd_de <= pixel_active;
                {lcd_r,lcd_g,lcd_b} <= pixel_active ? pixel_rgb : 18'd0;
                frame_start <= h_count == 0 && v_count == 0;
                if (h_count == 530) begin
                    h_count <= 0;
                    v_count <= v_count == 291 ? 9'd0 : v_count + 1'b1;
                    pixel_y <= v_count == 291 ? (ROTATE_180 ? 9'd283 : 9'd500) :
                        ROTATE_180 ? pixel_y - 1'b1 : pixel_y + 1'b1;
                end else begin
                    h_count <= h_count + 1'b1;
                end
            end else phase <= phase + 1'b1;
        end
    end
endmodule
