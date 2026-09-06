module xinxian_top #(
    parameter integer CLK_HZ   = 50000000,
    parameter integer BLINK_HZ = 1
) (
    input  wire sys_clk_50m,
    input  wire rst_n,
    output wire led
);

    localparam integer HALF_PERIOD = CLK_HZ / (BLINK_HZ * 2);

    reg [1:0]  rst_pipe;
    reg [31:0] blink_count;
    reg        led_reg;

    // 异步复位，同步释放
    always @(posedge sys_clk_50m or negedge rst_n) begin
        if (!rst_n)
            rst_pipe <= 2'b00;
        else
            rst_pipe <= {rst_pipe[0], 1'b1};
    end

    // 50 MHz 时钟下约 1 Hz 闪烁
    always @(posedge sys_clk_50m) begin
        if (!rst_pipe[1]) begin
            blink_count <= 32'd0;
            led_reg     <= 1'b0;
        end
        else if (blink_count == HALF_PERIOD - 1) begin
            blink_count <= 32'd0;
            led_reg     <= ~led_reg;
        end
        else begin
            blink_count <= blink_count + 1'b1;
        end
    end

    assign led = led_reg;

endmodule