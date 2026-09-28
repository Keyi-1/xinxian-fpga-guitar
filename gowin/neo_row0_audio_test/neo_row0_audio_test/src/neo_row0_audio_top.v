module neo_row0_audio_top #(
    // 12.288 MHz 下约 5 ms 防抖
    parameter integer DEBOUNCE_CYCLES = 61440
) (
    input  wire audio_clk_12m288,
    input  wire rst_n,

    input  wire COL0,
    input  wire COL1,
    input  wire COL2,
    input  wire COL3,
    input  wire COL4,
    input  wire COL5,
    input  wire COL6,
    input  wire COL7,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n
);

    // ------------------------------------------------------------
    // 音频域复位：异步置位、两拍同步释放
    // ------------------------------------------------------------

    reg [1:0] audio_rst_sync;
    wire      audio_rst_n;

    always @(posedge audio_clk_12m288 or negedge rst_n) begin
        if (!rst_n)
            audio_rst_sync <= 2'b00;
        else
            audio_rst_sync <= {audio_rst_sync[0], 1'b1};
    end

    assign audio_rst_n = audio_rst_sync[1];

    // ------------------------------------------------------------
    // COL 输入同步
    // ------------------------------------------------------------

    wire [7:0] col_in_n;
    wire [7:0] pressed_now;

    reg [7:0] col_meta;
    reg [7:0] col_sync;

    assign col_in_n = {
        COL7, COL6, COL5, COL4,
        COL3, COL2, COL1, COL0
    };

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            col_meta <= 8'hff;
            col_sync <= 8'hff;
        end
        else begin
            col_meta <= col_in_n;
            col_sync <= col_meta;
        end
    end

    // 品位板 COL 低有效
    assign pressed_now = ~col_sync;

    // ------------------------------------------------------------
    // 8 位整体防抖
    // ------------------------------------------------------------

    reg [7:0]  candidate_mask;
    reg [7:0]  stable_mask;
    reg [15:0] debounce_count;

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            candidate_mask <= 8'd0;
            stable_mask    <= 8'd0;
            debounce_count <= 16'd0;
        end
        else if (pressed_now != candidate_mask) begin
            candidate_mask <= pressed_now;
            debounce_count <= 16'd0;
        end
        else if (debounce_count < DEBOUNCE_CYCLES - 1) begin
            debounce_count <= debounce_count + 1'b1;
        end
        else begin
            stable_mask <= candidate_mask;
        end
    end

    // ------------------------------------------------------------
    // 最高品优先
    //
    // COL0 = 第1品
    // ...
    // COL7 = 第8品
    // 无按键 = 第0品/空弦
    // ------------------------------------------------------------

    function [3:0] highest_fret;
        input [7:0] mask;
        integer k;
        begin
            highest_fret = 4'd0;

            // 后面的高位会覆盖前面的低位，因此最高品优先。
            for (k = 0; k < 8; k = k + 1) begin
                if (mask[k])
                    highest_fret = k + 1;
            end
        end
    endfunction

    wire [3:0] selected_fret;

    assign selected_fret = highest_fret(stable_mask);

    // ------------------------------------------------------------
    // ROW0 对应第1弦 E4
    //
    // ROM 地址：
    //   0 = E4 空弦
    //   1 = F4
    //   ...
    //   8 = C5
    // ------------------------------------------------------------

    wire [5:0]  phase_addr;
    wire [31:0] selected_phase_inc;

    assign phase_addr = {2'b00, selected_fret};

    note_phase_table u_note_phase_table (
        .addr     (phase_addr),
        .phase_inc(selected_phase_inc)
    );

    // ------------------------------------------------------------
    // 保留已验证的持续测试音触发方式
    // ------------------------------------------------------------

    wire note_on;
    wire voice_active;

    test_tone_trigger u_test_tone_trigger (
        .clk    (audio_clk_12m288),
        .rst_n  (audio_rst_n),
        .note_on(note_on)
    );

    minimal_audio_output u_minimal_audio_output (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (audio_rst_n),

        .note_on      (note_on),
        .note_off     (1'b0),
        .phase_inc    (selected_phase_inc),

        .sample_tick  (),
        .voice_active (voice_active),
        .pcm16_valid  (),

        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    // NEO Dock 功放低有效；复位时强制关闭。
    assign pa_en_n = audio_rst_n ? ~voice_active : 1'b1;

endmodule