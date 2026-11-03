# 正式 FPGA 工程

入口：`neo_guitar_touch_game.gprj`，顶层 `neo_guitar_touch_game_top`，器件 `GW5AT-LV60PG484AC1/I0 / Device B`。使用 Gowin EDA V1.9.12.03 x64，Synthesize → Place & Route，输出 `impl/pnr/neo_guitar_touch_game.fs`。

本工程引用仓库根目录 `rtl/`、`mem/`、`constraints/`，保持原相对路径。不要只复制gprj。受保护的 `impl/neo_guitar_touch_game_process_config.json` 保留原字节。

直接上板可使用[已验收FS](../../releases/fpga/neo_guitar_touch_game.fs)，原IDE输出和固定发布相互独立。[完整构建说明](../../docs/BUILDING.md)、[接线与Flash下载](../../docs/HARDWARE.md)、[当前验证范围](../../docs/VALIDATION.md)。历史阶段README、构建脚本及收据移至 `verification/gowin/neo_guitar_touch_game/`。
