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

    // KEY0 低电平异步复位；释放只在音频时钟域内同步完成。
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

    // NEO Dock 31005 PA_EN 低有效；音频域复位期间保持关闭。
    assign pa_en_n = audio_rst_n ? ~core_pa_enable : 1'b1;

endmodule
