# Tang Mega 60K / NEO Dock 板级集成审查

审查日期：2026-09-19

## 1. 审查结论

当前 `full_guitar_top` 已经覆盖产品的完整逻辑链路，但它此前仍是“逻辑顶层”，不是可直接烧录的 NEO Dock 板级顶层。现新增 `neo_full_guitar_top` 作为电气边界层，仅处理已确认的接口语义，不写入任何未经核验的物理引脚。

在取得实物底板版本号、LCD 模组/FPC 定义、琴颈与 MCP3208 的最终接线表之前，不应为该板级顶层创建 CST，也不应生成或烧录带自动引脚的 bitstream。

## 2. 已确认的硬件资源

- 核心器件：`GW5AT-LV60PG484AC1/I0`，Gowin 选择 `GW5AT-60B / PBG484A / Device Version B`。
- NEO Dock 与 Tang Mega 60K/138K 共用同一系列底板外设，但不同 SOM、底板修订版与复用接口仍需用对应版本资料核验。
- 核心板固定 50 MHz 输入在官方 60K 示例中使用 `V22`。
- NEO Dock 包含 PT8211、耳机/扬声器输出、3 个用户按键、并行 RGB LCD 接口、2 路差分 ADC、SD、HDMI、DDR3、USB3/CH569、以太网等资源。
- 板载 ADC 只有 2 路差分输入，不满足四根弦的独立采样需求；外接 MCP3208 方案合理且继续保留。
- NEO Dock 31004 音频原理图的功放控制语义为高电平关闭、低电平开启。板级输出因此使用 `pa_en_n`，并在复位及无声部活动时保持高电平静音。
- 官方 138K 共用底板音频示例给出的 PT8211 网络候选为 `BCLK=Y17`、`LRCK=AB17`、`DIN=AA16`、`PA_EN=AB16`。这些值只作为交叉核对证据，未直接写入本项目 60K CST。
- LCD 连接器宣称支持 RGB888，但官方示例常使用 RGB666；最终输出位宽、PCLK 极性、同步极性、背光控制和 FPC 引脚必须以实际面板和底板版本确认。
- MS5351 的用户时钟输入脚随 NEO Dock 修订版变化，31004 与 31005+ 不同；目前不把它作为产品固定时钟源。音频继续使用外部 12.288 MHz 有源晶振，显示时钟最终由 FPGA PLL 产生。

官方资料入口：

- Sipeed Tang Mega 60K Wiki：<https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html>
- Sipeed 60K 示例：<https://github.com/sipeed/TangMega-60K-example>
- Sipeed 138K 共用底板示例：<https://github.com/sipeed/TangMega-138K-example>

### 2.1 官方资料快照与约束可信度

本次复核锁定到以下官方仓库快照：

- 60K 示例：`f0347d830305ef3efb921f47bb51701e569beefd`；
- 138K 共用底板示例：`06e7d8b118d345915ab6f257b7c22226f81575cd`。

60K 官方 `pmod_led_neo` 约束可以确认：50 MHz 时钟使用 `V22/LVCMOS33`；`Y12`、`AA13`、`AB13` 是 1.5 V 上拉按键输入所用的球位集合；两组 PMOD 候选共给出 16 根 3.3 V GPIO，并且与 DVP/顶部 2×20 排针复用。不同官方示例对三枚按键使用 `rst_n`、`key0`、`key1` 的命名并不一致，因此只确认球位集合，不在本项目中猜测 KEY1/2/3 的物理对应关系。

同一 60K 官方快照中，`audio_i2s/README.md` 和 `audio_sd/README.md` 仍为 `TBD`，也没有 60K 专用 PT8211 或 RGB LCD 约束可直接复用。138K 示例里的 PT8211 和 RGB666 约束只能证明共用 NEO Dock 的网络候选，不能替代 60K、实际 PCB 版本和 LCD FPC 的最终核验。

MS5351 资料还存在官方来源间的不一致：60K `pmod_led_neo` 对 31005+ 的注释写 `V13`，而后续官方时钟说明写 `V10`；31004 均指向 `AB12`。在实物版本和原理图确认前，本项目不会使用其中任何一个值。

## 3. 当前接口覆盖

| 板级功能 | FULL RTL 状态 | 板级处理 | 结论 |
| --- | --- | --- | --- |
| 50 MHz 系统时钟 | 已使用 | 顶层输入 | 待写入经核验 CST |
| 12.288 MHz 音频时钟 | 已使用 | 顶层输入 | 使用外部晶振，待确认接线脚 |
| LCD 像素时钟 | 逻辑已使用 | 当前仍为顶层输入，输出 `lcd_pclk` 极性参数化 | 板级 PLL 尚未接入 |
| 4×8 琴颈矩阵 | 已使用 | 四根扫描线实现低电平/高阻切换 | 待确认 12 根 GPIO |
| MCP3208 四通道 | 已使用 | SPI 已接入 FULL 链路 | 待确认外接插座和 SPI GPIO |
| KEY1/2/3 | 已接入 | 去抖、单次切换、2FF CDC | 对应音色/合唱/延音混响 |
| PT8211 | 已接入 | BCLK/LRCK/DIN 输出 | 待以 60K 对应资料确认物理脚 |
| 功放使能 | 已接入 | 修正为低有效 `pa_en_n` | 复位和空闲时静音 |
| RGB LCD | 已接入 | RGB888、HS/VS/DE/PCLK/BL | 位宽和面板时序待实物确认 |
| 运行健康信号 | RTL 内已有 | `deadline_miss`、显示 CDC overrun、ADC/琴颈观测点未接到板级调试出口 | 上板验收前应做最小可观测性接入 |
| DDR3/HDMI/SD/USB3/网口 | 未使用 | 无 | 首版无需求，不为提高利用率而加入 |

### 3.1 已完成逻辑但尚未完成的板级接入

1. `neo_full_guitar_top` 已覆盖琴颈矩阵、MCP3208、三个功能键、PT8211、功放静音和 RGB LCD 电气边界；音频主链路本身没有待补接的功能模块。
2. `pixel_clk` 仍从板级顶层输入，尚未实例化面向最终 LCD 时序的 Gowin PLL；这是当前最明确的板级时钟缺口。
3. 12.288 MHz 音频参考按需求继续采用外部有源晶振，但其输入插座、3.3 V 兼容球位和布线尚未冻结。若未来考虑由 MS5351 提供，必须使用纯 HDL 配置并先解决上述版本/引脚冲突，不能依赖 MCU 运行时服务。
4. RGB888 到 RGB666 的可选边界收窄尚未加入，因为实际连接器位宽、FPC 和面板仍未确认；现在提前加入只会固化猜测。
5. `deadline_miss` 在谐波输出链内部生成后未向 FULL 顶层引出；显示 CDC overrun、声部活动、原始 ADC、峰值、品位状态和事件时间戳也主要停留在内部观测点。仿真已覆盖这些条件，但实机验收仍需要 GAO 或少量粘滞故障标志。

### 3.2 外设取舍

首版应继续使用现有三枚按键、PT8211、耳机/扬声器和 RGB LCD，并把外接 MCP3208、4×8 琴颈矩阵及音频参考时钟接到经核验的 3.3 V 扩展 GPIO。两组 PMOD 只有 16 根候选 GPIO，恰好等于矩阵 12 根加 MCP3208 四线 SPI，不能在未做完整复用/冲突表前再假定其中还有音频时钟余量。

可以合理保留的后续扩展只有两类：

- 利用 MCP3208 剩余四通道加入有明确演奏价值的旋钮/踏板，例如总音量或效果深度；判定和映射仍由 RTL 完成；
- 为上板验收加入最小硬件可观测性，例如 GAO、一个粘滞错误标志或明确需要的调试引脚，不把普通状态灯当成功能填充。

当前不建议接入板载双通道 ADC、DDR3、HDMI、SD、USB3/CH569、以太网、摄像头、麦克风阵列或风扇。板载 ADC 无法替代四弦独立采样；其余外设不解决首版乐器闭环中的缺口，反而增加引脚复用、时钟或协议风险。

## 4. 本阶段验证

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

下一项合理工作不是增加新音效或占用更多外设，而是完成“可核验的物理板级连接矩阵”。需要先取得：

1. 实物 NEO Dock PCB 版本（尤其 31004 或 31005+）；
2. Tang Mega 60K 对应版本的官方完整 pin constraints；
3. 实际 LCD 模组型号、FPC pinout、RGB666/888 位宽和时序；
4. 外部 12.288 MHz 晶振、MCP3208 和 4×8 琴颈矩阵的接线表。

资料到齐后先形成端口—连接器—FPGA 球位—I/O bank—电压—复用冲突表，并由实物丝印/原理图复核。通过该表后，下一项 RTL 工作确定为板级时钟包装：从 50 MHz 产生最终 LCD 像素时钟，保留已经验证的外部 12.288 MHz 音频域，同时把 `deadline_miss`/CDC overrun 做成可观测的粘滞健康状态。然后才创建独立板级 CST，重新执行 `neo_full_guitar_top` 的布局布线与 I/O 电气检查。

资料确认前停止继续猜测引脚，不实现时钟包装，不生成可烧录 bitstream，也不扩展 DDR3、HDMI、SD、USB3 或软核 CPU。
