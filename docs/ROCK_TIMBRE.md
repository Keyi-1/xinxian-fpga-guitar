# 第三音色的当前实现

2026-10-05，用户要求弃用之前的重金属参考。第三音色当前为 **新哇音录音参考 V4，延长衰减**。
完整分析、工程、试听和验收见 [WAH_REFERENCE_TIMBRE.md](WAH_REFERENCE_TIMBRE.md)。

当前可下载位流：`build/wah_reference/neo_guitar_audio_full_wah_v4_long_decay.fs`。
当前无混响试听：`build/wah_reference/rtl_wah_long_dry.wav`。
无效果自然尾音约 1.16 秒，延音约 4.5 秒；前 42.67 ms 与 V3 相同，音高不变。
原钢琴、明亮弦音、三键功能及接线保持一致。

旧重金属 V1/V2 已退出当前生成和播放路径，旧位流及系数仅作历史备份：
`build/rock_reference/v1_before_tight_drive`、`build/wah_reference/replaced_rock_v2`。
旧数字验收记录：[V1](evidence/rock_timbre_acceptance.txt)、[V2](evidence/rock_timbre_v2_acceptance.txt)。
这些历史记录不代表当前 V4，也不代表主观听感已通过。
