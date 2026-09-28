module neo_row0_led_test #(
    // 共阴极/高电平点亮：0
    // 共阳极/低电平点亮：1
    parameter LED_ACTIVE_LOW = 1'b0
) (
    input  wire sys_clk_50m,
    input  wire rst_n,

    input  wire COL0,
    input  wire COL1,
    input  wire COL2,
    input  wire COL3,
    input  wire COL4,
    input  wire COL5,
    input  wire COL6,
    input  wire COL7,

    output wire LED0,
    output wire LED1,
    output wire LED2,
    output wire LED3,
    output wire LED4,
    output wire LED5,
    output wire LED6,
    output wire LED7
);

    wire [7:0] col_in_n;
    wire [7:0] pressed_now;
    wire [7:0] led_value;

    reg [7:0] col_meta;
    reg [7:0] col_sync;

    reg [7:0] previous_sample;
    reg [7:0] stable_pressed;

    reg [17:0] sample_counter;

    assign col_in_n = {
        COL7, COL6, COL5, COL4,
        COL3, COL2, COL1, COL0
    };

    // 两级同步，降低异步按键输入的亚稳态风险。
    always @(posedge sys_clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            col_meta <= 8'hff;
            col_sync <= 8'hff;
        end
        else begin
            col_meta <= col_in_n;
            col_sync <= col_meta;
        end
    end

    // ROW0 固定接地，按下后相应 COL 被拉低。
    assign pressed_now = ~col_sync;

    // 50 MHz / 250000 = 5 ms。
    // 连续两个样本相同后更新，防抖时间约 10 ms。
    always @(posedge sys_clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter  <= 18'd0;
            previous_sample <= 8'd0;
            stable_pressed  <= 8'd0;
        end
        else if (sample_counter == 18'd249999) begin
            sample_counter <= 18'd0;

            if (pressed_now == previous_sample)
                stable_pressed <= pressed_now;

            previous_sample <= pressed_now;
        end
        else begin
            sample_counter <= sample_counter + 1'b1;
        end
    end

    assign led_value = LED_ACTIVE_LOW
                     ? ~stable_pressed
                     :  stable_pressed;

    assign LED0 = led_value[0];
    assign LED1 = led_value[1];
    assign LED2 = led_value[2];
    assign LED3 = led_value[3];
    assign LED4 = led_value[4];
    assign LED5 = led_value[5];
    assign LED6 = led_value[6];
    assign LED7 = led_value[7];

endmodule
