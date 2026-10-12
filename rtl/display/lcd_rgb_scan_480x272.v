// Verified Tang Mega 60K + NEO Dock 31005 panel timing, 50 MHz / 6.
// All logic remains in the board-clock domain. RGB is sampled here at the
// falling DCLK edge, giving the panel 60 ns before its next rising edge.
module lcd_rgb_scan_480x272 (
    input wire clk,
    input wire rst_n,
    input wire [17:0] pixel_rgb,
    output wire [8:0] pixel_x,
    output wire [8:0] pixel_y,
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
    assign pixel_x = h_count[8:0] - 9'd43;
    assign pixel_y = v_count - 9'd12;
    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= 0;
            h_count <= 0;
            v_count <= 0;
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
                end else h_count <= h_count + 1'b1;
            end else phase <= phase + 1'b1;
        end
    end
endmodule
