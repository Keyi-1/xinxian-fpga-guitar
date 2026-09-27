module neo_minimal_audio_top (
    input  wire sys_clk_50m,
    input  wire audio_clk_12m288,
    input  wire rst_n,

    output wire dac_bclk,
    output wire dac_lrck,
    output wire dac_din,
    output wire pa_en_n
);

    wire core_pa_enable;

    minimal_top u_minimal_top (
        .sys_clk_50m      (sys_clk_50m),
        .audio_clk_12m288 (audio_clk_12m288),
        .rst_n            (rst_n),
        .dac_bclk         (dac_bclk),
        .dac_lrck         (dac_lrck),
        .dac_din          (dac_din),
        .pa_en            (core_pa_enable),
        .led              ()
    );

    // NEO Dock 31005 PA_EN 低有效；复位期间保持关闭
    assign pa_en_n = rst_n ? ~core_pa_enable : 1'b1;

endmodule