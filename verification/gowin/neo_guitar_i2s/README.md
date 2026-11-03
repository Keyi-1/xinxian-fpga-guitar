# 双音频输出：PT8211 + 标准 I²S

打开 `neo_guitar_i2s.gprj`，顶层为 `neo_guitar_i2s_top`。
在当前程序生成钢琴瞬态和圆形频谱/李萨如渐暗版上，增加 J9 标准 I²S，
保留全部板载声音和画面。既有工程默认关闭新接口，新工程启用它。

本机可直接在 Gowin Programmer 中加载
`build/releases/dual_i2s/neo_guitar_i2s.fs`，无需重新编译。
该文件已通过固定引脚布线、时序及综合网表对照，
SHA256 为 `9849f4669ad555e16cced7d00b33a29ada22439c0a6f0fb78cb387b3c1358b84`。
发布目录同时保存对应 `verification.json`。
该记录对应原数字验证构建；后续 IDE 重编译产生的 `impl` 网表／位流须重新验证，
不能与原网表仿真证据混用。本机保存的发布副本继续独立保留。

先关闭工程，执行 `configure_ide.ps1`，再重新打开工程。
Place=4、Route=2、Clock Route Order=1，hold 修复开启，CPU/SSPI/I2C 复用脚为 GPIO。
IDE 配置 JSON 随工程保存，Tcl `build.tcl` 也采用相同设置。

完整接线、协议、外接 DAC 配置、验证和复现步骤见
[标准 I²S 验证接口说明](../../docs/STANDARD_I2S_VALIDATION.md)。

| J9 | 信号 | 球位 |
| --- | --- | --- |
| 11 | BCLK，3.072 MHz | P19 |
| 12 | WS/LRCK，48 kHz | R19 |
| 9 | DATA，16 有效位/32 位时隙 | T21 |
| 3 或 4 | 共地 | GND |

板载 PT8211 原接线不变。新增输出均为 LVCMOS33，不接外部主动时钟输出。
J17 1–2 继续保持牢固连接。上述 GPIO 不与现用矩阵/ADC/LCD/LED 重叠；
它们还与 SDRAM1/DVP 复用，不可让该类外设同时驱动这些网络。

实际固定引脚实现：Logic 47470/59904、Register 18733/60780、CLS 26282/29952，
BSRAM 86/118、DSP 115.5/118。新增发送逻辑未增加 DSP 或 BSRAM。
音频/系统 Fmax 为 14.340/59.995 MHz，满足 12.288/50 MHz；setup/hold 违规均为 0。
验证结果、输入来源和下载文件哈希由 `check_result.py` 核对后保存到 `verification.json`。
最终综合网表验证：7632 个 PT8211 帧与 RTL 完全一致，7631 对完整 I²S 样本
与 PT8211 一致；7,949,456 个系统时钟、1,115,060 个 LCD 有效像素与 RTL 一致。
网表仿真的 225 条警告均为厂商存储器模型中的已知未用宽度分支，无其他警告或错误。
2026-10-13，用户确认当前程序已通过下板验收，作为 master 的当前整机入口。
外接 DAC 的型号和专项测量结果尚未单独记录。
