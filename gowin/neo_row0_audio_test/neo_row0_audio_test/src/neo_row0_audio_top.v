`include "guitar_config.vh"

// 4 根弦各自独立发声（取消弦间优先级），同一根弦内取最高品位。
// 包含独立音频域二级消抖与精确采样单脉冲触发，防止多弦齐按时的声音抖动。
module neo_row0_audio_top #(
    parameter integer MATRIX_CLK_DIV         = 25000,
    parameter integer MATRIX_DEBOUNCE_FRAMES = 3,
    parameter integer SAMPLE_DIV             = `AUDIO_SAMPLE_DIV,
    parameter integer PT8211_REF_DIV         = `PT8211_REF_DIV
) (
    input  wire sys_clk_50m,
    input  wire audio_clk_12m288,
    input  wire rst_n,

    inout  wire ROW0,
    inout  wire ROW1,
    inout  wire ROW2,
    inout  wire ROW3,

    input  wire COL0,
    input  wire COL1,
    input  wire COL2,
    input  wire COL3,
    input  wire COL4,
    input  wire COL5,
    input  wire COL6,
    input  wire COL7,

    output wire DBG0,
    output wire DBG1,
    output wire DBG2,
    output wire DBG3,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n
);

    // ============================================================
    // 1. COL 输入同步（50 MHz 域）
    // ============================================================
    wire [7:0] col_async = {COL7, COL6, COL5, COL4, COL3, COL2, COL1, COL0};
    reg  [7:0] col_meta, col_sync;

    always @(posedge sys_clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            col_meta <= 8'hFF;
            col_sync <= 8'hFF;
        end else begin
            col_meta <= col_async;
            col_sync <= col_meta;
        end
    end

    // ============================================================
    // 2. 4x8 矩阵扫描例化
    // ============================================================
    wire [3:0]  row_oe;
    wire [15:0] fret_id_sys; // {弦3, 弦2, 弦1, 弦0}

    assign ROW0 = row_oe[0] ? 1'b0 : 1'bz;
    assign ROW1 = row_oe[1] ? 1'b0 : 1'bz;
    assign ROW2 = row_oe[2] ? 1'b0 : 1'bz;
    assign ROW3 = row_oe[3] ? 1'b0 : 1'bz;

    matrix_scanner #(
        .CLK_DIV        (MATRIX_CLK_DIV),
        .DEBOUNCE_FRAMES(MATRIX_DEBOUNCE_FRAMES)
    ) u_matrix_scanner (
        .clk           (sys_clk_50m),
        .rst_n         (rst_n),
        .col_in_n      (col_sync),
        .row_oe        (row_oe),
        .stable_fret_id(fret_id_sys)
    );

    // ============================================================
    // 3. 音频域复位（异步置位、同步释放）
    // ============================================================
    reg [1:0] audio_rst_sync;
    always @(posedge audio_clk_12m288 or negedge rst_n) begin
        if (!rst_n)
            audio_rst_sync <= 2'b00;
        else
            audio_rst_sync <= {audio_rst_sync[0], 1'b1};
    end
    wire audio_rst_n = audio_rst_sync[1];

    // ============================================================
    // 4. 品位跨时钟域：两级同步及双拍锁定
    // ============================================================
    reg [15:0] fid_meta, fid_sync, fid_prev, fret_audio;

    always @(posedge audio_clk_12m288) begin
        if (!audio_rst_n) begin
            fid_meta   <= 16'd0;
            fid_sync   <= 16'd0;
            fid_prev   <= 16'd0;
            fret_audio <= 16'd0;
        end else begin
            fid_meta <= fret_id_sys;
            fid_sync <= fid_meta;
            fid_prev <= fid_sync;
            if (fid_sync == fid_prev)
                fret_audio <= fid_sync;
        end
    end

    // ============================================================
    // 5. 四根弦独立音高表、独立防抖触发与声部实例化
    // ============================================================
    wire [3:0]  tick_w;
    wire [3:0]  active_w;
    wire [3:0]  valid_w;
    wire [95:0] pcm_w;

    wire common_tick = tick_w[0]; // 四个声部采样时钟对齐

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_string
            localparam [5:0] BASE = i * 9;

            wire [3:0] fret_cur = fret_audio[4*i +: 4];
            reg  [3:0] fret_last;
            reg  [3:0] fret_ok;
            reg  [3:0] fret_hold;
            reg  [8:0] stab_cnt;
            reg        on_pend;
            reg        off_pend;
            reg        note_on_r;
            reg        note_off_r;

            always @(posedge audio_clk_12m288) begin
                if (!audio_rst_n) begin
                    fret_last  <= 4'd0;
                    fret_ok    <= 4'd0;
                    fret_hold  <= 4'd0;
                    stab_cnt   <= 9'd0;
                    on_pend    <= 1'b0;
                    off_pend   <= 1'b0;
                    note_on_r  <= 1'b0;
                    note_off_r <= 1'b0;
                end else begin
                    // 仅在采样 Tick 到来时同步产生 1 周期脉冲给包络，彻底杜绝防抖抖动
                    if (common_tick) begin
                        note_on_r  <= on_pend;
                        note_off_r <= off_pend;
                        on_pend    <= 1'b0;
                        off_pend   <= 1'b0;
                    end

                    // 每根弦独立的防抖与变化检测
                    if (fret_cur != fret_last) begin
                        fret_last <= fret_cur;
                        stab_cnt  <= 9'd0;
                    end
                    else if (stab_cnt < 9'd480) begin // 稳定持续约 10ms (480 个采样点)
                        stab_cnt <= stab_cnt + 1'b1;
                        if (stab_cnt == 9'd479 && fret_cur != fret_ok) begin
                            fret_ok <= fret_cur;
                            if (fret_cur != 4'd0) begin
                                fret_hold <= fret_cur;
                                on_pend   <= 1'b1;
                            end else begin
                                off_pend  <= 1'b1;
                            end
                        end
                    end
                end
            end

            wire [5:0]  phase_addr = BASE + {2'b00, fret_hold};
            wire [31:0] phase_inc;

            note_phase_table u_note_phase (
                .addr     (phase_addr),
                .phase_inc(phase_inc)
            );

            voice_audio_core #(
                .SAMPLE_DIV(SAMPLE_DIV)
            ) u_voice (
                .clk_audio_ref (audio_clk_12m288),
                .rst_n         (audio_rst_n),
                .note_on       (note_on_r),
                .note_off      (note_off_r),
                .velocity_level(2'b11),
                .phase_inc     (phase_inc),
                .sample_tick   (tick_w[i]),
                .sample_valid  (valid_w[i]),
                .pcm_out       (pcm_w[24*i +: 24]),
                .env_level     (),
                .active        (active_w[i])
            );
        end
    endgenerate

    // ============================================================
    // 6. 四路混音：相加后右移 2 位（÷4），无溢出爆音
    // ============================================================
    wire signed [23:0] p0 = pcm_w[23:0];
    wire signed [23:0] p1 = pcm_w[47:24];
    wire signed [23:0] p2 = pcm_w[71:48];
    wire signed [23:0] p3 = pcm_w[95:72];

    wire signed [25:0] mix_sum = p0 + p1 + p2 + p3;
    wire signed [23:0] mix_pcm = mix_sum[25:2];

    wire               pcm16_valid;
    wire signed [15:0] pcm16_out;

    pcm24_to_16 u_pcm24_to_16 (
        .clk         (audio_clk_12m288),
        .rst_n       (audio_rst_n),
        .pcm_valid   (valid_w[0]),
        .pcm_in      (mix_pcm),
        .sample_valid(pcm16_valid),
        .sample_out  (pcm16_out)
    );

    // ============================================================
    // 7. PT8211 发送驱动
    // ============================================================
    pt8211_tx #(
        .REF_DIV(PT8211_REF_DIV)
    ) u_pt8211_tx (
        .clk_audio_ref(audio_clk_12m288),
        .rst_n        (audio_rst_n),
        .sample_valid (pcm16_valid),
        .sample_left  (pcm16_out),
        .sample_right (pcm16_out),
        .dac_bclk     (dac_bclk),
        .dac_lrck     (dac_lrck),
        .dac_din      (dac_din)
    );

    // 有任意弦发声时解静音，全部静音时拉高静音
    assign pa_en_n = audio_rst_n ? ~(|active_w) : 1'b1;

    // 调试输出
    assign DBG0 = fret_audio[0];
    assign DBG1 = fret_audio[1];
    assign DBG2 = fret_audio[2];
    assign DBG3 = fret_audio[3];

endmodule