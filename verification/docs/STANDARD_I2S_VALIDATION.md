# 标准 I²S 比赛验证接口

本版在 `experiment/procedural-piano-hammer` 的 `e55c7cb` 基础上增加标准 I²S。
板载 PT8211、程序生成的钢琴击弦瞬态、钢琴主体、亮弦、wah、和声、合唱、
混响、松品续音、左侧弦彩条、圆形频谱与李萨如渐暗均保留。
数字接口实时发送合成结果，不存放或播放预录音频。

## 1. 下载与构建

使用 `gowin/neo_guitar_i2s/neo_guitar_i2s.gprj`，顶层 `neo_guitar_i2s_top`。
本机已验证下载文件为 `build/releases/dual_i2s/neo_guitar_i2s.fs`，
可直接由 Gowin Programmer 下载，不必重新编译。
先关闭工程，再执行该目录的 `configure_ide.ps1`，然后重新打开 `.gprj`。
IDE Configuration 中确认 Place Option=4、Route Option=2、Clock Route Order=1、
Correct Hold Violation 开启，以及 CPU/SSPI/I2C 引脚作为普通 GPIO。
这里的 CPU 设置只释放复用引脚，不实例化或运行处理器。

```powershell
# 当前目录：仓库根目录
& '.\gowin\neo_guitar_i2s\configure_ide.ps1'
# 若用 Tcl 构建，工作目录设为新工程目录。
Set-Location '.\gowin\neo_guitar_i2s'
& 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build.tcl *> build_console.log
```

原有工程的 `I2S_ENABLE` 默认为 0，不增加外部输出脚；新工程设置为 1。
已有工程的源文件清单也已补充 `i2s_tx.v`，不必手动补齐依赖。
既有 52 个球位和原时钟约束保留，新工程增加三个 3.3 V GPIO。
LCD 继续使用 J5，J17 1–2 保持牢固连接。

## 2. 接线

| 信号 | NEO Dock 31005 接口 | Mega 60K PG484 球位 | 对接模块/分析仪 |
| --- | --- | --- | --- |
| `i2s_bclk` | J9-11 / PMOD0_IO0 | P19，Bank 7，LVCMOS33 | BCK/BCLK |
| `i2s_ws` | J9-12 / PMOD0_IO1 | R19，Bank 7，LVCMOS33 | LRCK/LCK/WS |
| `i2s_data` | J9-9 / PMOD0_IO2 | T21，Bank 7，LVCMOS33 | DIN/DATA |
| GND | J9-3 或 J9-4 | 地 | GND |

这三个 GPIO 与当前 J13 按品矩阵、J8 ADC、J9-7/8/5/6 状态 LED、J5 LCD、
板载 DAC 不重叠。J9 的针号按原理图和板上标记确认，不按视角猜左右顺序。
这些 GPIO 还与 SDRAM1/DVP 摄像头复用，因此新增接口使用期间不要让
J14 的 SDRAM1 模块或 DVP 摄像头驱动同一网络。

依据：底板原理图第 19 页 J9、第 6 页 J0 到 PMOD 的连接；
60K 30354 核心板原理图第 5 页 Bank 7。底板原理图中的 Bank 名称对应 138K，
本工程电压/Bank 使用 60K 核心板信息，不直接沿用 138K Bank 编号。

逻辑分析仪只需这四根线，输入应支持 3.3 V。外接 DAC 另需按模块说明供电。
采样率建议至少 25 MS/s，条件允许时用 50 MS/s，以清楚观察半个 BCLK 的边沿间隔。
FPGA 是 BCLK/WS 的发送端，接收端使用从机模式，不再反向驱动时钟。

## 3. 协议与样本

- 采样率 48 kHz，BCLK 3.072 MHz，占空比 50%，每帧 64 个 BCLK。
- 左/右各 32 个位时钟；WS=0 指示左声道，WS=1 指示右声道。
- 有效数据为 16 位有符号补码，MSB 先发送，之后补 16 个零。
- WS 切换所在的位仍属于前一声道；下一个位才是新声道 MSB。
- DATA/WS 在 BCLK 下降沿更新，接收端在上升沿采样。

这符合 [NXP I²S 规范 §3](https://www.nxp.com/docs/en/user-manual/UM11732.pdf)。
逻辑分析仪选 Philips/标准 I²S、上升沿采样、32 位声道字长；解码得到的
32 位字的高 16 位就是现有板载输出样本，低 16 位为零。
如果软件分别设置有效位与时隙，设置有效位 16、时隙 32。

`four_string_board_audio_chain.v` 仍只运行一套合成与音效：

```text
四弦音源 → 立体声/和声/合唱/混响 → PCM24 转 PCM16
                                      ├→ 原 PT8211 → 板载音箱
                                      └→ 新 i2s_tx → J9 / 外接 DAC
```

两个发送模块在相同音频时钟的帧边界提交同一对样本。
整帧保持左右声道一致，帧边界同时出现的 `sample_valid` 优先于旧 pending 样本。
复位清空当前与等待样本，输出静音；运行时若没有新样本，则重复上一对，
沿用 PT8211 的策略。正常生产路径每 256 个参考时钟提供一对样本。
接口不是任意速率 FIFO：上游最多每帧提交一对，不能用于更快的样本源。
参数启用 I²S 时要求 PT8211 `REF_DIV` 为偶数且 `SAMPLE_DIV=64*REF_DIV`；
本板使用 4/256，对应 I²S 分频 2。

新 SDC 将三个串行输出从寄存器到 GPIO 的延迟限制为 40 ns，
不对这些路径设置 false path。半个 BCLK 为 162.76 ns，最坏 40 ns 引脚间
延迟差后仍有 122.76 ns 的板端建立/保持预算；外接连线和模块需实测确认。

## 4. 外接 PCM5102A

PCM5102A 支持 48 kHz / 64fs BCLK，即 3.072 MHz，并可用 BCLK PLL 做三线接收。
具体见 [TI 数据手册 §9.3.5.3、表 11](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)。
对应配置是标准 I²S（FMT 低）、SCK/MCLK 保持地电平以启用内部 PLL、
XSMT 解除静音；模块已带跳线/上拉时以其实际电路为准。
BCK、LRCK、DIN 与表中对应连接，共地。芯片逻辑使用 3.3 V；某些模块
VIN 带稳压器可接受 5 V，不代表裸芯片或 GPIO 可接 5 V。
输出是线路电平，接有源音箱/后级功放；板载音箱仍可同时使用。

## 5. 已执行的验证及复现

```powershell
# 仓库根目录；ModelSim 位置可通过参数覆盖。
& '.\tools\run_i2s_checks.ps1'
& '.\gowin\neo_guitar_i2s\run_gate_check.ps1' `
  -ModelSimBin 'S:\BaiduNetdiskDownload\modelsim\win64'
& 'E:\anaconda3\python.exe' gowin/neo_guitar_i2s/check_result.py
```

协议独立接收器已验证 309 对样本：声道顺序、16 位补零、WS 一位延迟、
位时钟周期、边界同周期更新、不同提交相位、输入断流保留及声道中途复位。
每轮复位发送 100 对独特样本，包含正负极值，逐帧匹配，无正常输入丢样或重复。
可打开 `sim/temp/i2s/i2s_tx.vcd` 查看实际仿真波形。
本轮从该 VCD 导出的截图保存在本机 `build/dual_i2s/i2s_one_bit_delay.png`：
WS 下降沿到左声道 MSB 更新实测为一个 BCLK，即 325.520 ns。

完整音频链与 `e55c7cb` 原链在 2,097,153 个参考时钟上完全一致：
8192 对标准 I²S 样本与实际 PT8211 引脚解码逐帧一致，8188 帧非零。
钢琴/亮弦/wah、合唱、混响、和声、延音、松品续音及重拨都在测试序列中。
同时检查最终 PCM 连续以 256 个参考时钟为间隔输出，没有样本丢失或重复。

综合层次报告的新增 `standard_i2s.u_tx` 为 59 个寄存器、91 个 LUT、5 个 ALU，
不含 DSP 或 BSRAM。2026-10-13 固定引脚布局布线已完成：Logic 47470/59904、
Register 18733/60780、CLS 26282/29952、BSRAM 86/118、DSP 115.5/118；
音频/系统 Fmax 为 14.340/59.995 MHz，setup/hold 违规均为 0。
布线资源、Fmax、setup/hold、源码和下载文件哈希
由新工程 `verification.json` 记录，校验器会拒绝失败构建或来源不一致的网表。
最终综合网表对照也已完成：7632 帧实际 PT8211 数据与 RTL 一致，
7631 对完整标准 I²S 样本与实际 PT8211 一致，三根串行引脚与 RTL 逐时钟一致；
LCD 的 7,949,456 个系统时钟及 1,115,060 个有效像素与 RTL 一致。
测试结束时最后一帧 I²S 仍在发送补零尾部，因此完整配对数比 PT8211 少一，
不表示丢样。网表仿真只有厂商原语未用存储宽度分支的 225 条已知警告。
2026-10-13，用户确认当前双音频输出程序已通过下板验收。
外接 DAC 的型号和专项测量结果尚未单独记录，可继续补充现场波形及联调记录。
