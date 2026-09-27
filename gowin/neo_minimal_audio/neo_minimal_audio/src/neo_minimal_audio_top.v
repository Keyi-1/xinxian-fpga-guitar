module neo_minimal_audio_top (
    input  wire sys_clk_50m,
    input  wire audio_clk_12m288,
    input  wire rst_n,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n
);

    reg [1:0] audio_rst_sync;
    wire      audio_rst_n;
    wire      core_pa_enable;

    // 异步置位复位、在 12.288 MHz 音频域同步释放
    always @(posedge audio_clk_12m288 or negedge rst_n) begin
        if (!rst_n)
            audio_rst_sync <= 2'b00;
        else
            audio_rst_sync <= {audio_rst_sync[0], 1'b1};
    end

    assign audio_rst_n = audio_rst_sync[1];

    minimal_top u_minimal_top (
        .sys_clk_50m      (sys_clk_50m),
        .audio_clk_12m288 (audio_clk_12m288),
        .rst_n            (audio_rst_n),
        .dac_bclk         (dac_bclk),
        .dac_lrck         (dac_lrck),
        .dac_din          (dac_din),
        .pa_en            (core_pa_enable),
        .led              ()
    );

    // 复位期间关闭功放；声部活动时拉低使能
    assign pa_en_n = audio_rst_n ? ~core_pa_enable : 1'b1;

endmodule