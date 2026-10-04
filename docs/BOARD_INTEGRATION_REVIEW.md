# Tang Mega 60K / NEO Dock 板级集成审查

审查日期：2026-09-27

> **2026-10-03 更新：** 用户已确认双 PCB 全链路实物测试结果理想，正式主工程已同步。
> 当前矩阵使用已实测的 **J13**、ADC 使用 **J8**；以
> [主工程同步说明](MAIN_ENGINE_SYNC.md)、[全链路接线表](NEO_FULL_CHAIN_AUDIO_TEST.md)
> 和 `constraints/neo_guitar_main.cst` 为当前接线依据。下面 2026-09-27 的 PMOD 候选、
> Bank 1 通用禁用、MCP3208 待验证以及按音符关闭 PA 的描述均是历史记录，
> 不再约束已实测的这套 J13/J8 方案。当前 PA 仅在复位期间关闭。
> 核心板版本仍未进一步确认；LCD、效果按键和新增外设分配继续单独审核。


## 1. 审查结论

当前 `full_guitar_top` 已经覆盖产品的完整逻辑链路，但它仍是“逻辑顶层”，不是可直接烧录的 NEO Dock 板级顶层。`neo_full_guitar_top` 作为电气边界层处理矩阵三态、按键、PT8211、功放和 LCD 端口语义，尚未绑定正式物理引脚。

实物底板已确认是 NEO Dock 31005。核心板因无法从底板拆下，只能确定为 30353 或 30354；两版主体定义相同，但第 6 页电源设计存在差异，因此在核心板版本确认前禁止使用 Bank 1。`MINIMAL` 专用 CST/SDC、布局布线、SRAM bitstream 和实物 E4 音频闭环已经验证成功；FULL 自动引脚实现继续仅作为规模/时序基线，严禁烧录。MCP3208、矩阵和 LCD 仍须分别审核后接入。

## 2. 已确认的硬件资源

- 核心器件：`GW5AT-LV60PG484AC1/I0`，Gowin 选择 `GW5AT-60B / PBG484A / Device Version B`。
- 实物 NEO Dock 修订版为 31005；Tang Mega 60K 核心板为 30353/30354 之一，暂时不能进一步确认。
- 核心板固定 50 MHz 输入在官方 60K 示例中使用 `V22`。
- NEO Dock 包含 PT8211、耳机/扬声器输出、3 个用户按键、并行 RGB LCD 接口、2 路差分 ADC、SD、HDMI、DDR3、USB3/CH569、以太网等资源。
- 板载 ADC 只有 2 路差分输入，不满足四根弦的独立采样需求；外接 MCP3208 方案合理且继续保留。
- NEO Dock 31005 音频原理图确认功放控制语义为高电平关闭、低电平开启。板级输出因此使用 `pa_en_n`，并在复位及无声部活动时保持高电平静音。
- PT8211 网络已经由 31005 原理图、30353/30354 共同 BTB 定义、官方 60K CST和官方 138K 共用底板音频示例交叉确认：`BCLK=Y17`、`LRCK=AB17`、`DIN=AA16`、`PA_EN=AB16`，均为不受核心板版本差异影响的 Bank 7 3.3 V 球位。
- NEO Dock 31005 的 J5 使用 RGB888 针脚排列，但底板只把 R2-R7、G2-G7、B2-B7 连接到 FPGA/CH569 复用总线。FPGA 可控颜色数据是 RGB666/18 bit，接口为并行 TTL/DPI RGB，不是 LVDS。
- MS5351M 的 CLK2 通过 `USR_CLK_IN` 接入 V13。示波器和 MINIMAL 实物音频链均已验证 12.288 MHz；完整断电后 CLK2 可独立自动恢复，不依赖电脑、MCU、BL616 运行时服务或软核 CPU。

官方资料入口：

- Sipeed Tang Mega 60K Wiki：<https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html>
- Sipeed 60K 示例：<https://github.com/sipeed/TangMega-60K-example>
- Sipeed 138K 共用底板音频说明：<https://github.com/sipeed/TangMega-138K-example/blob/main/audio_i2s/audio_i2s.md>
- Sipeed 138K PT8211 串行器：<https://github.com/sipeed/TangMega-138K-example/blob/main/audio_i2s/eda_proj/src/audio_drive.v>
- Sipeed 138K 音频顶层与约束：<https://github.com/sipeed/TangMega-138K-example/blob/main/audio_i2s/eda_proj/src/top.v>、<https://github.com/sipeed/TangMega-138K-example/blob/main/audio_i2s/eda_proj/src/audio.cst>

### 2.1 官方资料快照与约束可信度

本次复核锁定到以下官方仓库快照：

- 60K 示例：`f0347d830305ef3efb921f47bb51701e569beefd`；
- 138K 共用底板示例：`06e7d8b118d345915ab6f257b7c22226f81575cd`。

60K 官方 `pmod_led_neo` 约束可以确认：50 MHz 时钟使用 `V22/LVCMOS33`；`Y12`、`AA13`、`AB13` 是 1.5 V 上拉按键输入所用的球位集合；两组 PMOD 候选共给出 16 根 3.3 V GPIO，并且与 DVP/顶部 2×20 排针复用。不同官方示例对三枚按键使用 `rst_n`、`key0`、`key1` 的命名并不一致，因此只确认球位集合，不在本项目中猜测 KEY1/2/3 的物理对应关系。

同一 60K 官方快照中，`audio_i2s/README.md` 和 `audio_sd/README.md` 仍为 `TBD`，没有可直接复用的 60K 音频 RTL。官方 138K `audio_i2s` 示例已作为次级参考审查：它确认相同 NEO Dock 上的 PT8211/功放球位，并演示 16-bit、MSB-first、每帧 32 个 BCLK 的串行发送。该示例面向 `GW5AST-138`，使用 138K 专用 CST、内部振荡器、138K PLL 和一个甚至带有 GW2AR 器件头信息的 `CLKDIV` 包装，因此这些器件原语、时钟 IP、复位脚和工程文件不得复制到 60K 工程。

138K 示例把 `PA_EN` 直接置 `0` 以常开功放，这与 31005 原理图的低有效语义一致，但其顶层注释写成“高电平有效”，注释与实际电路行为不一致。本项目继续以原理图为准，并保持复位/空闲时高电平静音。其简单 400 Hz 波形 ROM和串行器也不替换本项目已经通过 testbench 的 E4 `MINIMAL`、PCM16 转换和 `pt8211_tx`；只用于上板时比对 BCLK/LRCK/DIN 波形。

此前不同官方页面对 MS5351 31005+ 的球位描述存在 `V13` 与 `V10` 不一致。现在以 31005 实物、31005 原理图 J2-88、两版 60K 核心板共同 BTB 定义和实际 CLK2 测量为依据，`USR_CLK_IN=V13` 已进入连接矩阵；V10 不使用。

## 3. 当前接口覆盖

| 板级功能 | FULL RTL 状态 | 板级处理 | 结论 |
| --- | --- | --- | --- |
| 50 MHz 系统时钟 | 已使用 | 顶层输入，V22 | 已确认，待审核后写入专用 CST |
| 12.288 MHz 音频时钟 | 已使用 | MS5351 CLK2 -> `USR_CLK_IN` -> V13 | 示波器、FPGA 音频链及断电重启已验证 |
| LCD 像素时钟 | 逻辑已使用 | 当前仍为顶层输入，输出 `lcd_pclk` 极性参数化 | 板级 PLL 尚未接入 |
| 4×8 琴颈矩阵 | 已使用 | ROW0 临时使用 PMOD1 八列输入和 PMOD0 八 LED；最终仍为 12 线候选 | ROW0 单组初步实物通过；完整扫描未验收 |
| MCP3208 四通道 | 已使用 | PMOD1 余下四线 SPI 安全候选 | 待实际线束确认 |
| KEY1/2/3 | 已接入 | 三枚 Bank 9 1.5 V 用户按键 | 与独立复位合计需要四路，当前存在资源冲突 |
| PT8211 | 已接入 | BCLK/LRCK/DIN 输出 | Y17/AB17/AA16 已确认 |
| 功放使能 | 已接入 | 修正为低有效 `pa_en_n` | 复位和空闲时静音 |
| RGB LCD | 已接入 | 内部 RGB888；未来板级只输出 `[7:2]` | 31005 物理数据为 RGB666，面板未采购，暂缓约束 |
| 运行健康信号 | RTL 内已有 | `deadline_miss`、显示 CDC overrun、ADC/琴颈观测点未接到板级调试出口 | 上板验收前应做最小可观测性接入 |
| DDR3/HDMI/SD/USB3/网口 | 未使用 | 无 | 首版无需求，不为提高利用率而加入 |

### 3.1 已完成逻辑但尚未完成的板级接入

1. `neo_full_guitar_top` 已覆盖琴颈矩阵、MCP3208、三个功能键、PT8211、功放静音和 RGB LCD 电气边界；音频主链路本身没有待补接的功能模块。
2. `neo_minimal_audio_top` 已把 `minimal_top.pa_en` 高有效活动请求转换为复位安全的低有效 `pa_en_n`，并对外部 KEY0 复位执行音频域异步置位、两拍同步释放；实物和专用 testbench 均已通过。
3. MS5351M CLK2 到 V13 的物理路径、12.288 MHz 频率和完整断电后的独立恢复均已确认，当前 MINIMAL 不依赖 MCU、软核 CPU、BL616 运行时服务或上位机。
4. `pixel_clk` 仍从板级顶层输入，最终 LCD 的 PLL、RGB888 到物理 RGB666 的边界截位以及同步/背光配置均等待实际面板定型；LCD 未采购前不实现、不约束。
5. `deadline_miss` 在谐波输出链内部生成后未向 FULL 顶层引出；显示 CDC overrun、声部活动、原始 ADC、峰值、品位状态和事件时间戳也主要停留在内部观测点。仿真已覆盖这些条件，但实机验收仍需要 GAO 或少量粘滞故障标志。

### 3.2 外设取舍

首版应先使用现有三枚按键、PT8211 和耳机/扬声器；LCD 等待采购及接口确认。外接 MCP3208 与 4×8 琴颈矩阵使用连接矩阵中列出的 3.3 V PMOD 候选。两组 PMOD 只有 16 根候选 GPIO，恰好等于矩阵 12 根加 MCP3208 四线 SPI，不能再假定其中还有其他功能余量。12.288 MHz 已经由板载 MS5351M CLK2 经 `USR_CLK_IN` 独立送入 V13，不占用 PMOD。

可以合理保留的后续扩展只有两类：

- 利用 MCP3208 剩余四通道加入有明确演奏价值的旋钮/踏板，例如总音量或效果深度；判定和映射仍由 RTL 完成；
- 为上板验收加入最小硬件可观测性，例如 GAO、一个粘滞错误标志或明确需要的调试引脚，不把普通状态灯当成功能填充。

当前不建议接入板载双通道 ADC、DDR3、HDMI、SD、USB3/CH569、以太网、摄像头、麦克风阵列或风扇。板载 ADC 无法替代四弦独立采样；其余外设不解决首版乐器闭环中的缺口，反而增加引脚复用、时钟或协议风险。

## 4. 本阶段验证

### 4.1 MINIMAL 实物音频闭环

- 成功工程：`gowin/neo_minimal_audio/neo_minimal_audio`；成功 bitstream 为 `impl/pnr/neo_minimal_audio.fs`，目前仅通过 SRAM Program/Configure 使用，没有写入外部 Flash。
- 实物链路：12.288 MHz CLK2→E4 phase increment→`voice_audio_core`→PCM24/PCM16→`pt8211_tx`→NEO Dock PT8211→3.5 mm 左右声道。
- 输出频率约 329.63 Hz，左右声道正常，可持续发声，没有明显周期性爆音或断音。
- `KEY0/S4/AA13` 按住时静音，松开后 E4 自动恢复；`SW7/RECONFIG/N12` 是 FPGA 专用重配置按钮，SRAM 模式下按下会清除当前配置，并非 RTL reset。
- 运行中复位仿真通过：`PASS: MINIMAL runtime reset mutes and retriggers continuous E4`。完整记录见 `docs/evidence/neo_minimal_audio_acceptance.txt`。

### 4.2 ROW0 单组触点实物验证

- 独立工程：`gowin/neo_row0_led_test/neo_row0_led_test`，未覆盖音频 MINIMAL 或 FULL 实现。
- ROW0 固定接地，ROW1～ROW3 不连接；PMOD1 接八列，PMOD0 接八路调试 LED。用户实测 ROW0 八个品位的触点对应未发现问题。
- `process_config` 为 `"CPU": true`，允许 P19/R19/T21/U21 作为普通 GPIO；最终 P&R 日志中 PR2017=0、PR2028=0。
- 时序报告分析 158 个端点，setup/hold 违例均为 0；50 MHz 时钟实际 Fmax 148.111 MHz，最差 setup/hold slack 分别为 13.248 ns 和 0.247 ns。
- Pin Report 已确认 COL0～COL7 与 LED0～LED7 全部位于指定球位，Bank 1 使用量为 0。
- ModelSim 通过：`PASS: ROW0 columns debounce, mapping, multi-press and reset`。完整记录见 `docs/evidence/neo_row0_led_acceptance.txt`。

此结果严格限定为“ROW0 单组初步实物通过”，不能推导 ROW1～ROW3、完整 4×8 扫描、未选中行高阻、多行二极管防鬼键、四弦同时按键、同弦最高品优先或后续选音链已通过。

### 4.3 FULL 与板级封装既有验证

板级封装 testbench 验证：

- 每个扫描周期恰好一根矩阵行拉低，其余三根保持高阻；
- 三个按键通过去抖后各产生一次状态切换，长按不会重复切换；
- 按键状态通过双触发器同步进入音频域；
- 功放脚在空闲/复位时为高电平静音，在声部活动请求时为低电平开启；
- LCD 背光复位安全状态和 PCLK 参数化极性正确。

ModelSim 通过信息：

```text
PASS: NEO board wrapper tri-state/buttons/CDC/PA/LCD boundary
PASS: FULL matrix/ADC/four-voice/effects/PT8211/FFT/RGB frames=2000 spectrum=1 pixels=8558
```

Gowin 综合确认板级顶层可综合，并推断出 4 个 `TBUF`，对应四根矩阵扫描线的真实三态驱动。加入各时钟域复位同步后的最新综合资源为：

- Logic：25,646 / 59,904（43%）
- Register：11,461 / 60,780（19%，Latch=0）
- BSRAM：12 / 118（11%）
- I/O buffer：16 IBUF、36 OBUF、4 TBUF

该综合结果保存在：

```text
T:\Documents\AMD\gowin_neo_reset_synth\impl\gwsynthesis
```

## 5. 保留的 FULL 实现基线

现有逻辑顶层的完整 Gowin 布局布线结果保留在：

```text
T:\Documents\AMD\gowin_full_build\impl\pnr
```

该基线无 setup/hold 违例，三时钟最差结果如下：

| 时钟域 | 要求 | 实际 Fmax |
| --- | ---: | ---: |
| `sys_clk_50m` | 50.000 MHz | 126.622 MHz |
| `audio_clk_12m288` | 12.288 MHz | 21.989 MHz |
| `pixel_clk` | 33.333 MHz | 140.181 MHz |

该结果使用自动引脚，只证明逻辑规模和时序可实现；对应 `.fs` 不可烧录。

完成异步置位、各时钟域同步释放的复位修正后，又在独立目录完成了一次 FULL 布局布线；上述原始基线未被覆盖。最新结果保存在：

```text
T:\Documents\AMD\gowin_full_reset_build\impl\pnr
```

| 时钟域 | 要求 | 最新 Fmax |
| --- | ---: | ---: |
| `sys_clk_50m` | 50.000 MHz | 142.758 MHz |
| `audio_clk_12m288` | 12.288 MHz | 21.825 MHz |
| `pixel_clk` | 33.333 MHz | 132.019 MHz |

最新实现分析 35,241 个端点，setup/hold 违例均为 0，最差 setup slack 为 12.995 ns，最差 hold slack 为 0.158 ns。资源为 Logic 25,779/59,904（44%）、Register 11,343/60,780（19%，Latch=0）、BSRAM 14/118（12%）、DSP 40/118（34%）、I/O 65/297（22%）。工具功耗估算为 105.893 mW，但在没有实测负载和活动率前不作为硬件验收数据。

最新结果仍为自动引脚实现，只证明复位修正后的逻辑规模和时序可实现；对应 `.fs` 同样不可烧录。完整哈希和回归结果见 `docs/evidence/full_reset_timing_acceptance.txt`。

## 6. 下一步门槛与决定

“顶层端口—底板连接器—底板网络—BTB 针脚—FPGA 球位—实际 Bank—VCCIO—复用冲突—确认状态”表已经建立，MINIMAL 音频和 ROW0 单组均已完成初步实物闭环。矩阵下一阶段按以下顺序推进：

1. 继续使用现有临时 COL+LED 工程，断电后依次把固定接地线从 ROW0 移到 ROW1、ROW2、ROW3，每次只接地一行，其余行悬空，分别核对八触点；该阶段不改 CST、不做行扫描；
2. 四行单组通过后移除 PMOD0 调试 LED，恢复矩阵表中的 4 ROW + 8 COL 共 12 根 GPIO；P19/R19/T21/U21 继续要求 `CPU pins as regular I/O`；
3. 新的完整矩阵板级顶层直接实例化现有 `matrix_scanner`，用 GAO/JTAG 观察行选择、未选中行高阻、同步列输入、稳定矩阵和扫描周期，不复制扫描逻辑；
4. 依次验证单点、同行多点、跨行多点和会形成矩形组合的防鬼键测试，再验证 `fret_note_event` 的最高品优先及后续滑音/声部控制；
5. MCP3208 继续等待实际模块资料，LCD、三效果键资源冲突和物理延迟测试仍保留为独立后续门槛。

核心板版本继续标为 30353/30354 未确认，Bank 1 继续禁用。不得扩展 DDR3、HDMI、SD、USB3、CH569 或软核 CPU 来提高资源利用率，也不得覆盖成功 MINIMAL 工程或现有 FULL 自动引脚综合/布局布线基线。
