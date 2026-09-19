`timescale 1ns/1ps

module tb_rgb_spectrum_timing;
    reg pixel_clk;
    reg rst_n;
    wire [4:0] bar_read_index;
    reg [8:0] bar_height;
    reg [8:0] peak_height;
    wire lcd_hsync;
    wire lcd_vsync;
    wire lcd_de;
    wire [7:0] lcd_r;
    wire [7:0] lcd_g;
    wire [7:0] lcd_b;
    wire frame_start;
    wire [10:0] pixel_x;
    wire [9:0] pixel_y;

    localparam integer H_TOTAL = 64 + 2 + 4 + 2;
    localparam integer V_TOTAL = 32 + 1 + 2 + 1;

    rgb_spectrum_timing #(
        .H_ACTIVE(64), .H_FRONT(2), .H_SYNC(4), .H_BACK(2),
        .V_ACTIVE(32), .V_FRONT(1), .V_SYNC(2), .V_BACK(1),
        .BAR_SLOT(2), .BAR_WIDTH(1)
    ) dut (
        .pixel_clk(pixel_clk), .rst_n(rst_n),
        .bar_read_index(bar_read_index), .bar_height(bar_height),
        .peak_height(peak_height), .lcd_hsync(lcd_hsync),
        .lcd_vsync(lcd_vsync), .lcd_de(lcd_de), .lcd_r(lcd_r),
        .lcd_g(lcd_g), .lcd_b(lcd_b), .frame_start(frame_start),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    always #5 pixel_clk = ~pixel_clk;
    always @* begin
        bar_height = 9'd16 + bar_read_index[2:0];
        peak_height = 9'd24;
    end

    integer cycle_count;
    integer first_frame_cycle;
    integer second_frame_cycle;
    integer colored_pixels;
    integer hsync_low_cycles;
    integer vsync_low_cycles;

    always @(posedge pixel_clk) begin
        #1;
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (frame_start) begin
                if (first_frame_cycle < 0)
                    first_frame_cycle = cycle_count;
                else if (second_frame_cycle < 0)
                    second_frame_cycle = cycle_count;
            end
            if (lcd_de && ({lcd_r, lcd_g, lcd_b} != 24'd0))
                colored_pixels = colored_pixels + 1;
            if (!lcd_hsync) hsync_low_cycles = hsync_low_cycles + 1;
            if (!lcd_vsync) vsync_low_cycles = vsync_low_cycles + 1;
        end
    end

    initial begin
        pixel_clk = 1'b0;
        rst_n = 1'b0;
        cycle_count = 0;
        first_frame_cycle = -1;
        second_frame_cycle = -1;
        colored_pixels = 0;
        hsync_low_cycles = 0;
        vsync_low_cycles = 0;
        repeat (3) @(posedge pixel_clk);
        #1 rst_n = 1'b1;
        wait (second_frame_cycle >= 0);
        #1;
        if ((second_frame_cycle - first_frame_cycle) != H_TOTAL * V_TOTAL) begin
            $display("FAIL: RGB frame period got=%0d expected=%0d",
                     second_frame_cycle - first_frame_cycle, H_TOTAL * V_TOTAL);
            $finish;
        end
        if ((colored_pixels == 0) || (hsync_low_cycles == 0) ||
            (vsync_low_cycles == 0)) begin
            $display("FAIL: RGB renderer/timing inactive pixels=%0d hs=%0d vs=%0d",
                     colored_pixels, hsync_low_cycles, vsync_low_cycles);
            $finish;
        end
        $display("PASS: framebuffer-free RGB spectrum timing frame_cycles=%0d colored=%0d",
                 H_TOTAL * V_TOTAL, colored_pixels);
        $finish;
    end
endmodule
