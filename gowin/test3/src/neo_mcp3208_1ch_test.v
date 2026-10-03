`include "guitar_config.vh"

module neo_mcp3208_1ch_test #(
    parameter integer ADC_SPI_CLK_DIV   = `ADC_SPI_CLK_DIV,
    parameter integer SAMPLE_DIV        = `AUDIO_SAMPLE_DIV,
    parameter integer NOTE_HOLD_SAMPLES = 48000,

    parameter [11:0] ADC_BASELINE_CODE  = 12'd2053,  // 按实测稳态 0x803~0x807 中值更新
    parameter [11:0] TRIGGER_THRESHOLD  = 12'd100,
    parameter [11:0] REARM_THRESHOLD    = 12'd30,

    parameter        USE_ADC_VELOCITY   = 1'b0
) (
    input  wire audio_clk_12m288,
    input  wire rst_n,

    output wire adc_cs_n,
    output wire adc_sclk,
    output wire adc_mosi,
    input  wire adc_miso,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n,

    output wire event_led,
    output wire uart_tx
);

    localparam [31:0] PHASE_E4 = 32'h01C20D2F;

    // ============================================================
    // 1. MCP3208 单通道读取（内部已补偿右移一位的问题）
    // ============================================================
    wire        adc_sample_valid;
    wire [11:0] adc_sample_data;

    mcp3208_single_channel_reader #(
        .CLK_DIV(ADC_SPI_CLK_DIV)
    ) u_reader (
        .clk          (audio_clk_12m288),
        .rst_n        (rst_n),

        .adc_cs_n     (adc_cs_n),
        .adc_sclk     (adc_sclk),
        .adc_mosi     (adc_mosi),
        .adc_miso     (adc_miso),

        .sample_valid (adc_sample_valid),
        .sample_data  (adc_sample_data)
    );

    // ============================================================
    // 2. 拨弦检测（迟滞 + 死区）
    // ============================================================
    wire       pluck_valid;
    wire [1:0] detected_velocity;

    single_pluck_detector #(
        .TRIGGER_THRESHOLD(TRIGGER_THRESHOLD),
        .REARM_THRESHOLD  (REARM_THRESHOLD),
        .BASELINE_CODE    (ADC_BASELINE_CODE)
    ) u_detector (
        .clk            (audio_clk_12m288),
        .rst_n          (rst_n),
        .sample_valid   (adc_sample_valid),
        .sample_data    (adc_sample_data),
        .pluck_valid    (pluck_valid),
        .velocity_level (detected_velocity),
        .peak_magnitude ()
    );

    // ============================================================
    // 3. 触发事件 -> 采样域 note_on/note_off
    //    note_on/note_off 用电平(=pending_on/pending_off)，
    //    不用单拍脉冲，避免跟 sample_tick 错开一拍被包络错过
    // ============================================================
    wire              sample_tick;
    wire              voice_valid;
    wire signed [23:0] pcm_single;
    wire              voice_active;

    reg        pending_on;
    reg        pending_off;
    reg [31:0] hold_count;
    reg [1:0]  velocity_latched;

    wire note_on  = pending_on;
    wire note_off = pending_off;

    always @(posedge audio_clk_12m288) begin
        if (!rst_n) begin
            pending_on       <= 1'b0;
            pending_off      <= 1'b0;
            hold_count       <= 32'd0;
            velocity_latched <= 2'd3;
        end
        else begin
            if (pluck_valid) begin
                pending_on <= 1'b1;

                if (USE_ADC_VELOCITY)
                    velocity_latched <= detected_velocity;
                else
                    velocity_latched <= 2'd3;
            end

            if (sample_tick) begin
                if (pending_on) begin
                    pending_on <= 1'b0;
                    hold_count <= NOTE_HOLD_SAMPLES;
                end
                else if (hold_count != 0) begin
                    hold_count <= hold_count - 1'b1;

                    if (hold_count == 1)
                        pending_off <= 1'b1;
                end

                if (pending_off)
                    pending_off <= 1'b0;
            end
        end
    end

    // ============================================================
    // 4. 单声部音频核心
    // ============================================================
    voice_audio_core #(
        .SAMPLE_DIV(SAMPLE_DIV)
    ) u_voice (
        .clk_audio_ref  (audio_clk_12m288),
        .rst_n          (rst_n),

        .note_on        (note_on),
        .note_off       (note_off),
        .velocity_level (velocity_latched),
        .phase_inc      (PHASE_E4),

        .sample_tick    (sample_tick),
        .sample_valid   (voice_valid),
        .pcm_out        (pcm_single),
        .env_level      (),
        .active         (voice_active)
    );

    // ============================================================
    // 5. PCM 24位转16位
    // ============================================================
    wire              pcm16_valid;
    wire signed [15:0] pcm16_out;

    pcm24_to_16 u_pcm24_to_16 (
        .clk          (audio_clk_12m288),
        .rst_n        (rst_n),
        .pcm_valid    (voice_valid),
        .pcm_in       (pcm_single),
        .sample_valid (pcm16_valid),
        .sample_out   (pcm16_out)
    );

    // ============================================================
    // 6. PT8211 发送
    // ============================================================
    pt8211_tx #(
        .REF_DIV(`PT8211_REF_DIV)
    ) u_pt8211_tx (
        .clk_audio_ref (audio_clk_12m288),
        .rst_n         (rst_n),

        .sample_valid  (pcm16_valid),
        .sample_left   (pcm16_out),
        .sample_right  (pcm16_out),

        .dac_bclk      (dac_bclk),
        .dac_lrck      (dac_lrck),
        .dac_din       (dac_din)
    );

    assign pa_en_n = rst_n ? ~voice_active : 1'b1;

    // ============================================================
    // 7. 指示灯：拨一次亮一下（约 0.1 秒），与包络状态解耦
    //    低电平点亮
    // ============================================================
    reg [23:0] led_stretch_count;

    always @(posedge audio_clk_12m288) begin
        if (!rst_n) begin
            led_stretch_count <= 24'd0;
        end
        else begin
            if (pluck_valid)
                led_stretch_count <= 24'd1_200_000;
            else if (led_stretch_count != 0)
                led_stretch_count <= led_stretch_count - 1'b1;
        end
    end

    assign event_led = (led_stretch_count == 0);

    // ============================================================
    // 8. UART 调试：每 10ms 发送一次最新 ADC 值
    // ============================================================
    reg [16:0] uart_timer;
    reg        uart_send;
    reg [11:0] uart_adc_value;
    wire       uart_busy;

    always @(posedge audio_clk_12m288) begin
        if (!rst_n) begin
            uart_timer     <= 17'd0;
            uart_send      <= 1'b0;
            uart_adc_value <= 12'd0;
        end
        else begin
            uart_send <= 1'b0;

            if (adc_sample_valid)
                uart_adc_value <= adc_sample_data;

            if (uart_timer == 17'd122879) begin
                uart_timer <= 17'd0;

                if (!uart_busy)
                    uart_send <= 1'b1;
            end
            else begin
                uart_timer <= uart_timer + 1'b1;
            end
        end
    end

    adc_uart #(
        .CLK_HZ(12288000),
        .BAUD  (115200)
    ) u_adc_uart (
        .clk       (audio_clk_12m288),
        .rst_n     (rst_n),
        .send      (uart_send),
        .adc_value (uart_adc_value),
        .tx        (uart_tx),
        .busy      (uart_busy)
    );

endmodule