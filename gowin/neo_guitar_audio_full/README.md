# FULL 音频：三键、32 分量与钢琴音源

打开 `neo_guitar_audio_full.gprj`，Top=`neo_guitar_audio_full_top`，器件
`GW5AT-LV60PG484AC1/I0`，Device Version B。构建脚本固定上述设置：

```powershell
gw_sh.exe gowin/neo_guitar_audio_full/build.tcl
```

下载本目录 `impl/pnr/neo_guitar_audio_full.fs`。沿用现有 J13 矩阵、J8 MCP3208、
V13 的 12.288 MHz 时钟及 PT8211 接线，无需 LCD。
三个用户键全部用于控制，**没有外部复位输入**；配置后内部自动初始化。

| 用户键 | 操作 | 行为 |
| --- | --- | --- |
| USER_BUTTON1 / AA13 | 按一次 | 钢琴 → 明亮弦音 → 摇滚 → 钢琴，循环 |
| USER_BUTTON2 / AB13 | 短按松手 | 合唱开／关 |
| USER_BUTTON2 / AB13 | 按住约 1 秒 | 自动五度和声开／关；松手不会再切换合唱 |
| USER_BUTTON3 / Y12 | 按一次 | 无效果 → 延音 → 轻量混响 → 无效果，循环 |

上电为钢琴、合唱关闭、第三键无效果、和声关闭。和声在下一次拨弦时生效。
按键消抖约 20 ms，长按仅触发一次。第三键不影响合唱／和声开关。
当前 V2 让延音同时减慢空弦自然衰减，明亮弦音也有更长尾音；
合唱为 15～23 ms 左右反向调制延迟，轻混响增加回声配比与反馈尾音。
第三音色当前为新哇音参考 V4，包含半倍频与动态高频模态，包络衰减更慢：无效果约 1.16 秒归零，延音约 4.5 秒归零。
前 43 ms 起音、音高及采样表保持 V3 原样；无效果下松品仍按原阻尼收声。
请使用 `build/wah_reference/neo_guitar_audio_full_wah_v4_long_decay.fs` 或本目录的新构建输出；旧版仅留作历史备份。
LED0 熄灭／常亮／2 Hz 闪烁分别表示钢琴／明亮弦音／摇滚，低有效；
LED1/2/3 分别表示合唱、延音、轻混响；
第三键在“无效果”时，和声开启会同时点亮 LED2、LED3。

本工程包含与 LCD FULL 完全相同的音频核心、音效和 32 分量配置。
FFT/LCD 位于 `full_guitar_top`，数字验收已完成，真实 LCD 等采购及接口确认后接入。
`gowin/full_main_build/impl/pnr/full_guitar_top.fs` 使用自动引脚，只供逻辑实现检查。

[实现、资源和验收说明](../../docs/FULL_PIANO_EFFECTS.md) /
[第三音色新哇音参考与验收](../../docs/WAH_REFERENCE_TIMBRE.md) /
[V2 音效与试听](../../docs/FULL_EFFECTS_V2.md) /
[V2 数字证据](../../docs/evidence/full_effects_v2_acceptance.txt)。
