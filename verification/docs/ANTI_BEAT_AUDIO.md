# 三音以上的减拍频混音

更新：2026-10-04。用户反馈：耳机及两个扬声器均在三音及以上时出现难听的拍频；
当前两个音分别放到左右声道时没有该现象。根据这个现象，优先处理同声道内的多音叠加。
修改已经接入标准主工程，完成仿真、实际 RTL PCM 导出和固定引脚实现；实际听感尚待上板比较。

## 当前实现

实现文件为 `rtl/audio_io/four_voice_antibeat_allocator.v`，由
`four_string_board_audio_chain` 在逐弦合成之后、音效和 PCM16 转换之前调用。

1. 仍然最多四声部、每声道最多两个活动声部。最先出现的两个声部保持左右分离。
   第三个声部遇到两侧各有一个音时，比较目标音高差，优先进入频差较大的那侧。
   同音视为没有差频拍频；连续演奏及 Release 中已有声部保持原声道，重拨也不突然搬动声像。
   这是固定声像条件下的局部选择，并非遍历所有和弦的全局最优分配。
2. 同侧两个声部的实际 DDS 频差非零且小于 80 Hz 时，较早起音的声部增益降至 128/256，
   即半幅，约 -6 dB；新音保持 256/256。保留所有音高，也保留全部声部的合成和生命周期。
   原每侧混音除以二的余量仍保留。精确同音不触发该降幅。
3. 增益按每个 48 kHz 样本最多变化 2/256，半幅与全幅之间约需 1.33 ms。
   近邻结束、滑音离开范围后平滑恢复。重拨者重新获得全增益并从原 Attack 起音，
   同侧较早的伙伴随后平滑降幅。

单音、左右各一个音的增益保持原值。单独的声部内部 PCM、音高、Attack、自然衰减、
松品阻尼、ADC 触发和采样节奏不受混音策略影响。较早音的判定使用饱和样本年龄，
年龄同值时按声部索引定序；并非按 ADC 幅度动态压缩。

同声道中的等幅近邻正弦可以出现很深的周期性合成包络起伏。改变两音幅度比例会减浅这种起伏，
音高差选择也改变其调制频率。听觉粗糙度还取决于频率位置和各分音，
不能用一个固定 Hz 边界代表所有和弦。有关临界带和近邻分音的背景见
[Plomp 与 Levelt 原论文摘要](https://repository.tno.nl/SingleDoc?docId=69747)及
[Sethares 的原作者介绍](https://sethares.engr.wisc.edu/ttss.html)。
这里的 80 Hz 是当前工程的可调启发值，不是文献给出的通用阈值。

## 参数与回退

| 参数 | 默认 | 作用 |
| --- | --- | --- |
| `BOARD_ANTI_BEAT_ENABLE` | 1 | `rtl/config/guitar_config.vh` 中的默认开关 |
| `ANTI_BEAT_ENABLE` | 继承宏 | 标准主顶层、FULL、NEO FULL 和共享音频链的显式覆盖参数 |
| `ANTI_BEAT_GAP_HZ` | 80 | 物理主顶层、`guitar_audio_top` 和共享链可覆盖的近邻范围 |
| `ANTI_BEAT_PAIR_GAIN_Q8` | 128 | 同侧较早近邻音的增益；256 为原全幅 |
| `GAIN_STEP_Q8` | 2 | 分配模块的增益步长，按音频 sample tick 更新 |

若半幅使和弦层次变化过大，可在物理主顶层把 `ANTI_BEAT_PAIR_GAIN_Q8` 试为 192
（0.75，约 -2.5 dB），代价是减浅拍频的力度较弱。调整范围或增益后须重新构建和试听。
FULL/NEO FULL 直接暴露开关，范围和增益目前使用共享链默认值。

将 `BOARD_ANTI_BEAT_ENABLE` 改为 0 后重新构建，恢复原负载均衡动态硬立体声及原混音。
已通过实物的 `gowin/neo_full_chain_audio_test/src` 保留原样，仍可作为独立比较基线。

新可下载入口是 `gowin/xinxian_mega60k/xinxian_mega60k.gprj`，Top=`neo_guitar_main_top`，
位流为 `gowin/xinxian_mega60k/impl/pnr/neo_guitar_main.fs`。26 个引脚与原实测工程一致。
构建命令和主工程同步边界见 [主工程说明](MAIN_ENGINE_SYNC.md)。

## 实际 RTL A/B 试听及证据

`tb_antibeat_pcm_compare` 用同一稳定品位 `0x8852`（F#4/E4/D#4/A#3）、
固定力度 2 和同一拨弦序列，分别驱动关闭/开启策略的共享主音频链。
每版导出 96,000 个 PCM16 立体声帧；前一秒重复三音和弦，后一秒重复四音和弦。
波形来自真正的 Verilog 输出，没有用 Python 另行模拟合成，也没有分别做响度归一化。

- [组合试听 WAV](../build/antibeat/antibeat_comparison.wav)：原版 2 秒、静音 0.25 秒、新版 2 秒。
- [原版](../build/antibeat/antibeat_before.wav) / [新版](../build/antibeat/antibeat_after.wav)。
- [包络图](../build/antibeat/antibeat_envelope.png) / [数字测量记录](evidence/antibeat_pcm_comparison.txt)。

首个三音和弦起音后 40～160 ms，取双音声道的 Hilbert 包络，除以单音声道的包络去除共同自然衰减，
以 5%/95% 分位数计算起伏深度 `(P95-P05)/(P95+P05)`：

| 示例指标 | 关闭策略 | 开启策略 |
| --- | --- | --- |
| 归一化包络起伏深度 | 0.838158 | 0.489251 |
| 全片 PCM16 绝对峰值 | 24319 | 24221 |

这是一个构造和弦的数字对比。起伏变浅不等于所有和弦的主观粗糙度按同一比例下降，
也不是耳机或扬声器的实测声学指标。两声道在空气、后级或单声道下再相加仍可能出现拍频；
谐波路径的高次分音相互作用也未逐对建模。相邻半音、多种三/四音和弦、重拨及滑音应上板试听比较。
预期取舍是降低多音时的起伏，部分较早的和弦音会比原版轻。

复现（仓库根目录、PowerShell）：

```powershell
& ./sim/run_main_regression.ps1 -ModelSimBin '<ModelSim win64>' -Benches tb_four_voice_antibeat_allocator,tb_antibeat_pcm_compare
python tools/generate_antibeat_preview.py
```

生成器需要 NumPy，绘图另需 Matplotlib；WAV 写入使用 Python 标准库。
`build/` 和 `sim/temp` 是忽略目录，试听文件可用上述命令重建；数字证据随源码保存。

完整主回归 66 组通过，无 ModelSim Error/Fatal/Warning；分配测试覆盖所有首对双弦、第三/第四声部、
增益步长、重拨优先、同音及伙伴释放恢复；A/B 测试逐周期确认逐弦 PCM、生命周期和采样节奏一致。
另有八种滑音参数、32/26 位取值范围的等价测试，验证滑音运算化简保持原行为；
当前所有 ROM 音高完整保留，DDS 累加器仍为 32 位。
固定引脚主实现的 setup/hold 违例为 0，最终 Logic=11126、DSP=8，
主时钟 Fmax=12.503 MHz（需求 12.288 MHz）。详细结果见 [主工程数字验收](evidence/main_engine_sync_acceptance.txt)。
