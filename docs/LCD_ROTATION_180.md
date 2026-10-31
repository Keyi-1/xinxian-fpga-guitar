# LCD 整屏旋转 180°（2026-10-31）

基于 JDY-23 版本 `d5d85997ceee2db2b3120eedafb643955524e712`，仅修改三份 LCD 运行时源码。整屏使用逻辑坐标 `(479-x,271-y)`，上方对应 D、下方对应 A；文字、色块、游戏画面、频谱及曲线一起旋转。音频、曲库、串口、触控输入处理、引脚和时钟配置保持原版本。

## 下载与使用

[下载本次位流和验证报告](../build/releases/touch_game/lcd_rotate_20261031.zip)。解压后在 Gowin Programmer 中选择 `neo_guitar_touch_game_lcd_rotate_180.fs`。

位流 SHA256：`32bc37c33ccea5395239684743c6d394bb13bde2aa59d9c5d7b4d365afc9367d`。

本机新工程目录为 `E:\嵌入式\xinxian-fpga-guitar-lcd-rotate`；主工程下实际生成文件为 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，实际时序报告为同目录的 `neo_guitar_touch_game_tr_content.html`。为保留原本机工作区中未提交的修改，本次在从指定远端提交恢复的独立目录内，使用仓库现有 `.gprj` 和原配置，通过 `gw_sh` 执行 `open_project`、`run all`。未另设顶层或器件，未改写受保护的 process_config JSON。构建脚本为 `gowin/neo_guitar_touch_game/run_lcd_rotate_build.tcl`。

## 实现与验证

- `lcd_rgb_scan_480x272.v`：新增默认关闭的 `ROTATE_180` 参数；合并横坐标常量减法，纵坐标直接倒计数，保持 LCD 同步和六时钟像素周期。
- `guitar_radial_curve_renderer.v`：按倒序逻辑行预渲染，保留双扫描行缓冲与时限检查；默认参数仍兼容旧工程。
- `guitar_touch_game_display.v`：仅为主显示开启两处旋转参数。

Gowin V1.9.12.03、GW5AT-LV60PG484AC1/I0 Device B，2026-10-31 23:05:09 完成综合和完整布局布线。系统 Fmax **50.078 MHz**、音频 Fmax **18.291 MHz**，运行时钟仍为 50 / 12.288 MHz；setup、hold、锁存器、未布通网络均为 **0**。保留两条既有 PR1014 通用时钟布线提示，最终 STA 使用实际布线结果；系统时序余量仍较窄。

扫描器仿真通过两帧、261120 个有效像素的坐标映射、同步时序和 RGB 采样检查。倒序曲线渲染通过八组场景、2176 行的解析交点、覆盖范围、停音/尾迹和重复行触发检查，最慢 2266 / 3186 时钟，无超时。测试位于 `sim/tb_lcd_rotation.sv` 和 `sim/tb_lcd_rotation_curves.sv`。

本机 Icarus 12.0 devel 前端在生成 VVP 后异常退出；生成的两个 VVP 程序均实际运行通过，vvp 退出码为 0。生产综合由 Gowin 单独完成。完整输入、实际网表、位流与报告哈希见压缩包内 `verification.json`；仿真范围和失败候选记录见 `functional_validation.json`。独立恢复目录的其余 131 份构建输入与远端仅差末尾一个换行，未上传这些空白差异。

本次未烧录或进行实物屏幕验收，也不将这些专项仿真称为新的整机门级回归。此前已发布的固定版本和位流保留。
