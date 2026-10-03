`include "guitar_config.vh"

// 四通道 B 板测试：MCP3208 CH0..CH3 各自触发一根弦，固定音量，
// CH0=E4, CH1=B3, CH2=G3, CH3=D3，四路混音后送 PT8211。
module neo_mcp3208_4ch_audio_test #(
    parameter integer ADC_SPI_CLK_DIV   = `ADC_SPI_CLK_DIV,
    parameter integer SAMPLE_DIV        = `AUDIO_SAMPLE_DIV,
    parameter integer NOTE_HOLD_SAMPLES = 48000,
    parameter [11:0]  ADC_BASELINE_CODE = 12'd2053,
    parameter [11:0]  TRIGGER_THRESHOLD = 12'd100,
    parameter [11:0]  REARM_THRESHOLD   = 12'd30
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
    output wire [3:0] event_led
);

    localparam [31:0] PHASE_E4 = 32'h01C20D2F;
    localparam [31:0] PHASE_B3 = 32'h0151285D;
    localparam [31:0] PHASE_G3 = 32'h010B9A2B;
    localparam [31:0] PHASE_D3 = 32'h00C879A3;

    // ============================================================
    // 1. MCP3208 四通道轮询读取（已补偿位移）
    // ============================================================
    wire        adc_sample_valid;
    wire [1:0]  adc_sample_string;
    wire [11:0] adc_sample_data;

    mcp3208_four_channel_reader #(
        .CLK_DIV(ADC_SPI_CLK_DIV)
    ) u_reader (
        .clk          (audio_clk_12m288),
        .rst_n        (rst_n),
        .adc_cs_n     (adc_cs_n),
        .adc_sclk     (adc_sclk),
        .adc_mosi     (adc_mosi),
        .adc_miso     (adc_miso),
        .sample_valid (adc_sample_valid),
        .sample_string(adc_sample_string),
        .sample_data  (adc_sample_data)
    );

    // ============================================================
    // 2. 四弦独立拨弦检测
    // ============================================================
    wire [3:0] pluck_valid;

    four_string_pluck_detector #(
        .TRIGGER_THRESHOLD(TRIGGER_THRESHOLD),
        .REARM_THRESHOLD  (REARM_THRESHOLD),
        .BASELINE_CODE    (ADC_BASELINE_CODE)
    ) u_detector (
        .clk          (audio_clk_12m288),
        .rst_n        (rst_n),
        .sample_valid (adc_sample_valid),
        .sample_string(adc_sample_string),
        .sample_data  (adc_sample_data),
        .pluck_valid  (pluck_valid)
    );

    // ============================================================
    // 3. 四路独立 note_on/note_off + 定长响音
    //    note_on/note_off 用电平(=pending_on/pending_off)，
    //    不用单拍脉冲，避免和 sample_tick 错开一拍被包络错过
    // ============================================================
    wire        sample_tick;
    wire        pcm_mix_valid;
    wire signed [23:0] pcm_mix;
    wire [3:0]  voice_active;

    reg [3:0]  pending_on;
    reg [3:0]  pending_off;
    reg [31:0] hold_count [0:3];
    integer k;

    wire [3:0] note_on  = pending_on;
    wire [3:0] note_off = pending_off;

    always @(posedge audio_clk_12m288) begin
        if (!rst_n) begin
            pending_on  <= 4'd0;
            pending_off <= 4'd0;
            for (k = 0; k < 4; k = k + 1)
                hold_count[k] <= 32'd0;
        end
        else begin
            if (|pluck_valid)
                pending_on <= pending_on | pluck_valid;

            if (sample_tick) begin
                for (k = 0; k < 4; k = k + 1) begin
                    if (pending_on[k]) begin
                        pending_on[k] <= 1'b0;
                        hold_count[k] <= NOTE_HOLD_SAMPLES;
                    end
                    else if (hold_count[k] != 0) begin
                        hold_count[k] <= hold_count[k] - 1'b1;
                        if (hold_count[k] == 1)
                            pending_off[k] <= 1'b1;
                    end

                    if (pending_off[k])
                        pending_off[k] <= 1'b0;
                end
            end
        end
    end

    // ============================================================
    // 4. 四声部音频核心 + 混音（固定音量，velocity 全部最高档）
    // ============================================================
    four_voice_audio_core #(
        .SAMPLE_DIV(SAMPLE_DIV)
    ) u_four_voice_audio_core (
        .clk_audio_ref (audio_clk_12m288),
        .rst_n         (rst_n),
        .note_on       (note_on),
        .note_off      (note_off),
        .velocity_level(8'b11_11_11_11),
        .phase_inc     ({PHASE_D3, PHASE_G3, PHASE_B3, PHASE_E4}),
        .sample_tick   (sample_tick),
        .sample_valid  (pcm_mix_valid),
        .pcm_mix       (pcm_mix),
        .voice_active  (voice_active),
        .voice_pcm     ()
    );

    // ============================================================
    // 5. PCM 转换 + PT8211 输出
    // ============================================================
    wire        pcm16_valid;
    wire signed [15:0] pcm16_out;

    pcm24_to_16 u_pcm24_to_16 (
        .clk         (audio_clk_12m288),
        .rst_n       (rst_n),
        .pcm_valid   (pcm_mix_valid),
        .pcm_in      (pcm_mix),
        .sample_valid(pcm16_valid),
        .sample_out  (pcm16_out)
    );

    pt8211_tx #(.REF_DIV(`PT8211_REF_DIV)) u_pt8211_tx (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (rst_n),
        .sample_valid (pcm16_valid),
        .sample_left  (pcm16_out),
        .sample_right (pcm16_out),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    assign pa_en_n = rst_n ? ~(|voice_active) : 1'b1;

    // ============================================================
    // 6. 4 路指示灯，各自拨一次亮一下（约 0.1 秒），低电平点亮
    // ============================================================
    reg [23:0] led_stretch [0:3];
    integer m;

    always @(posedge audio_clk_12m288) begin
        if (!rst_n) begin
            for (m = 0; m < 4; m = m + 1)
                led_stretch[m] <= 24'd0;
        end
        else begin
            for (m = 0; m < 4; m = m + 1) begin
                if (pluck_valid[m])
                    led_stretch[m] <= 24'd1_200_000;
                else if (led_stretch[m] != 0)
                    led_stretch[m] <= led_stretch[m] - 1'b1;
            end
        end
    end

    assign event_led[0] = (led_stretch[0] == 0);
    assign event_led[1] = (led_stretch[1] == 0);
    assign event_led[2] = (led_stretch[2] == 0);
    assign event_led[3] = (led_stretch[3] == 0);

endmodule