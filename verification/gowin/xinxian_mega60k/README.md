# 双 PCB 主工程：成功固定钢琴基线

**2026-10-05：用户已确认本工程插值修复后的钢琴实物音色成功。**
新三键 FULL 音频位于 [`../neo_guitar_audio_full`](../neo_guitar_audio_full/README.md)，
它采用上电内部初始化，AA13 已改为音色键。本工程保留旧固定音色／AA13 复位基线。

打开 `xinxian_mega60k.gprj`，Top=`neo_guitar_main_top`，器件
`GW5AT-LV60PG484AC1/I0`，Version B。本工程直接使用仓库标准 `rtl/`，
并保留成功全链路测试的输入行为：静音选品、真实拨弦、平滑滑音、松品阻尼、
复位后 PA 常开、固定力度 2。当前 `feat/piano-hammer-voice` 试验分支默认启用
8 分音钢琴音源、短击弦起音、固定窄弦位立体声和公共轻混响。
音符表和接线未改变。用户报告上一版上板单音嘈杂，已复现并修复综合后包络偏移；
6696 帧真实 DAC 串行数据与 RTL 逐比特一致，当前修正版已由用户确认实物音色成功。
详见 [`docs/PIANO_FPGA_TRIAL.md`](../../docs/PIANO_FPGA_TRIAL.md)。
在 `rtl/config/guitar_config.vh` 设置 `BOARD_USE_PIANO=0` 并重新构建可恢复前一版音源；
同时设置 `BOARD_ANTI_BEAT_ENABLE=0` 可恢复原成功正弦混音。

接线与 `neo_full_chain_audio_test` 完全一致，26 个球位无冲突。
CST/SDC：`../../constraints/neo_guitar_main.cst`、`neo_guitar_main.sdc`。
标准 RTL 的 include/readmemh 依赖目录结构，不要单独复制其中一个源文件。

命令构建：`gw_sh.exe build.tcl`，脚本会自行切到本目录。
主位流：`impl/pnr/neo_guitar_main.fs`；先用同一接线做 SRAM 下载复核。
明确命名的修正版副本：`../../build/piano/neo_guitar_main_piano_interp_fix.fs`，
SHA256=`f74d926bcd300a187154338c236df87fe3609cd287479db7c62860ac20327af3`。
新位流已通过仿真和固定引脚实现，本次没有代替用户进行实际下载。

[完整同步说明](../../docs/MAIN_ENGINE_SYNC.md) /
[钢琴试验与实际 RTL 试听](../../docs/PIANO_FPGA_TRIAL.md) /
[减拍频策略与 A/B 试听](../../docs/ANTI_BEAT_AUDIO.md) /
[接线表](../../docs/NEO_FULL_CHAIN_AUDIO_TEST.md) /
[验收证据](../../docs/evidence/main_engine_sync_acceptance.txt)。

旧 `xinxian_top` LED 诊断源保留，但不再作为本主工程的顶层。
LCD 与三效果键不在当前接线范围；可选 FULL 的自动引脚位流不用于本机下载。
