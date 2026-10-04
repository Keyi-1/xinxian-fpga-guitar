# 双 PCB 主工程

打开 `xinxian_mega60k.gprj`，Top=`neo_guitar_main_top`，器件
`GW5AT-LV60PG484AC1/I0`，Version B。本工程直接使用仓库标准 `rtl/`，
并将成功全链路测试的行为同步为默认：静音选品、真实拨弦、自然尾音、
平滑滑音、动态硬立体声、复位后 PA 常开、固定力度 2。
另外默认开启新增减拍频混音：按音高选择声道，并平滑降低同声道近邻音中较早发声者的音量。
用户反馈前后版本的和弦听感仍不理想，最新钢琴参考分析与离线样音见
[`docs/PIANO_REFERENCE_ANALYSIS.md`](../../docs/PIANO_REFERENCE_ANALYSIS.md)；本工程尚未替换为钢琴音源。
在 `rtl/config/guitar_config.vh` 设置 `BOARD_ANTI_BEAT_ENABLE=0`
并重新构建可恢复原混音。

接线与 `neo_full_chain_audio_test` 完全一致，26 个球位无冲突。
CST/SDC：`../../constraints/neo_guitar_main.cst`、`neo_guitar_main.sdc`。
标准 RTL 的 include/readmemh 依赖目录结构，不要单独复制其中一个源文件。

命令构建：`gw_sh.exe build.tcl`，脚本会自行切到本目录。
主位流：`impl/pnr/neo_guitar_main.fs`；先用同一接线做 SRAM 下载复核。
新位流已通过仿真和固定引脚实现，本次没有代替用户进行实际下载。

[完整同步说明](../../docs/MAIN_ENGINE_SYNC.md) /
[减拍频策略与 A/B 试听](../../docs/ANTI_BEAT_AUDIO.md) /
[接线表](../../docs/NEO_FULL_CHAIN_AUDIO_TEST.md) /
[验收证据](../../docs/evidence/main_engine_sync_acceptance.txt)。

旧 `xinxian_top` LED 诊断源保留，但不再作为本主工程的顶层。
LCD 与三效果键不在当前接线范围；可选 FULL 的自动引脚位流不用于本机下载。
